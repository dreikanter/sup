require 'rbconfig'

WINDOWS = RbConfig::CONFIG['host_os'] =~ /mingw|mswin/i
DARWIN = RbConfig::CONFIG['host_os'] =~ /darwin/

require 'aws-sdk'
require 'clipboard'
require 'fileutils'
require 'json'
require 'filesize'
require 'listen'
require 'logger'
require 'rb-notifu'
require 'terminal-notifier' if DARWIN
require 'thor'
require 'uri'

module Logging
  DATETIME_FORMAT = '%Y-%m-%d %H:%M:%S'

  def logger
    @logger ||= Logger.new(STDOUT)
  end

  def init_logger(file_name,
                  verbose=false,
                  dt_format=Logging::DATETIME_FORMAT)
    @logger = Logger.new(file_name ? File.open(file_name, "a") : STDOUT)
    @logger.level = if verbose then Logger::DEBUG else Logger::INFO end
    @logger.datetime_format = dt_format
    @logger.formatter = proc do |severity, datetime, progname, msg|
      "#{datetime.strftime(dt_format)} #{severity}: #{msg}\n"
    end
  end
end

module Graphics
  DEFAULT_JPEG_QUALITY = 90
  PREVIEW_MAX_WIDTH    = 800
  PREVIEW_MAX_HEIGHT   = 800
  DEFAULT_LATENCY      = 0.5

  # ImageMagick's convert.
  def convert(src_file, dst_file, quality=nil)
    quality ||= Graphics::DEFAULT_JPEG_QUALITY
    options = '.jpg' == File.extname(dst_file) ? "-quality #{quality}" : ''
    return system("convert #{options} \"#{src_file}\" \"#{dst_file}\"")
  end

  def resize(src_file, dst_file, max_width, max_height, quality=nil)
    quality ||= Graphics::DEFAULT_JPEG_QUALITY
    options = []
    if WINDOWS
      options << "-resize \"#{max_width}x#{max_height}>\""
    else
      options << "-resize #{max_width}x#{max_height}\\>"
    end
    options << "-quality #{quality}" if '.jpg' == File.extname(dst_file)
    options = options.join(' ')
    return system("convert #{options} \"#{src_file}\" \"#{dst_file}\"")
  end

  def dimensions(file_name)
    width, height = `identify -format \"%w %h\" #{file_name}`.split
    return Integer(width), Integer(height)
  end
end

module Sup
  include Logging
  include Graphics

  # Constants
  META_DIR = 'meta'
  PREVIEW_DIR = 'preview'
  PROC_DIR = 'processed'
  ID_FILE = 'id.txt'
  CONFIG_FILE = File.join Dir.home, '.sup'
  LEGAL_EXTENSIONS = ['png', 'jpg']
  BAD_IDS = ['meta', 'fuck', 'bitch']

  # Defaults
  BASE_URL = 'http://<bucket>/'

  # Initialize everything.
  def init(path, bucket_name, args)
    init_logger(args[:log_file], args[:verbose] == true)

    @path = path
    @proc_dir = args[:proc_dir]
    if Pathname.new(@proc_dir).relative?
      @proc_dir = File.expand_path(@proc_dir, @path)
    end

    @bucket_name = bucket_name
    @bucket = get_bucket(@bucket_name)

    @base_url = args[:base_url]
    if Sup::BASE_URL == args[:base_url]
      @base_url = "http://#{@bucket_name}/"
    end

    @args = args

    id = last_id
    logger.info "last id is #{id.to_s(36)} (id)"
  end

  # Initializes S3 connection with access credentials from ~/.sup
  # configuration files, and returns bucket object.
  def get_bucket(bucket_name)
    config = Hash[*File.read(Sup::CONFIG_FILE).split(/[= \n]+/)]
    s3 = AWS::S3.new(
      access_key_id: config['access_key_id'],
      secret_access_key: config['secret_access_key'],
      s3_endpoint: config['s3_endpoint']
    )
    return s3.buckets[bucket_name]
  end

  # Cached id file name.
  def id_file
    File.join @path, Sup::ID_FILE
  end

  # Last integer id value from cache or bucket, if there are no cache.
  def last_id
    begin
      return Integer(File.read(id_file))
    rescue => e
      logger.debug "error reading id file: #{e}"
      return pull_last_id
    end
  end

  # Scan bucket objects for the last image id, and cache the integer value.
  def pull_last_id
    logger.info "scanning s3://#{@bucket_name} for last id"
    begin
      objects = @bucket.objects.with_prefix("#{Sup::META_DIR}/")
      id = (objects.map {|o| File.basename(o.key, '.*').to_i(36)}).max || 0
      File.write(id_file, id)
      return id
    rescue => e
      logger.error "error scanning for the last image id: #{e}"
      exit
    end
  end

  # Notify user.
  def notify(title, message)
    if WINDOWS
      Notifu::show(:title => title,
                   :message => message,
                   :type => :info,
                   :time => 2,
                   :nosound => true) do |status|
        if Notifu::ERRORS.include? status
          logger.error "notifu error: #{Notifu::ERRORS[status]}"
        end
      end
    elsif DARWIN
      TerminalNotifier.notify(message, :activate => url, :title => title)
    end
  end

  # Execute system command.
  def execute(cmd)
    logger.debug "exec: #{cmd}"
    return system(cmd)
  end

  # Swap graphic format name.
  def jpg_png(ext)
    'jpg' == ext ? 'png' : 'jpg'
  end

  def ensure_dir_exists(dir_path)
    FileUtils.mkdir_p(dir_path) unless File.directory? dir_path
  end

  # Converts image file to optimal format, generate metadata file,
  # and returns an array of generated file names.
  def process_image(src_file)
    ext = File.extname(src_file).downcase[1..-1]
    ext = 'jpg' if ext == 'jpeg'

    unless Sup::LEGAL_EXTENSIONS.include? ext
      logger.error "unsupported format: #{src_file}"
      raise
    end

    # Get new id
    id = last_id
    begin
      id36 = (id += 1).to_s(36)
    end while Sup::BAD_IDS.include? id36
    logger.info "new image id: #{id36} (#{id})"

    # Generating image copy in alternative format
    format = jpg_png(ext)
    key = "#{id36}.#{format}"
    dst_file = File.join(@proc_dir, key)
    ensure_dir_exists(@proc_dir)
    unless convert(src_file, dst_file, @args[:quality])
      logger.error "error converting source image"
      return nil
    end

    # Using most compact format
    src_size = File.size(src_file)
    dst_size = File.size(dst_file)
    if src_size <= dst_size
      File.unlink(dst_file)
      format = ext
      key = "#{id36}.#{format}"
      dst_file = File.join(@proc_dir, key)
      FileUtils.copy_file(src_file, dst_file)
    end

    files = [[key, ext2ctype(format), dst_file]]

    # Some logging
    max_size = [dst_size, src_size].max
    gain = (Float(dst_size - src_size).abs / max_size * 100).round(1)
    logger.info "#{format.upcase} is #{gain}% more compact"
    width, height = dimensions(dst_file)
    size = [dst_size, src_size].min
    pretty_size = Filesize.from("#{size} B").pretty
    logger.info "image size: #{pretty_size} (#{width}x#{height})"

    # Generate preview
    if @args[:preview]
      key = File.join(Sup::PREVIEW_DIR, "#{id36}.#{format}")
      dst_file = File.join(@proc_dir, key)
      files << [key, ext2ctype(format), dst_file]
      ensure_dir_exists(File.join(@proc_dir, Sup::PREVIEW_DIR))
      resize(src_file,
             dst_file,
             @args[:max_width],
             @args[:max_height],
             @args[:quality])
      preview_size = File.size(dst_file)
      pretty_size = Filesize.from("#{preview_size} B").pretty
      preview_width, preview_height = dimensions(dst_file)
      logger.info "preview size: #{pretty_size} " +
        "(#{preview_width}x#{preview_height})"
    else
      preview_size, preview_width, preview_height = nil, nil, nil
    end

    # Generate metadata file
    if @args[:meta]
      key = File.join(Sup::META_DIR, "#{id36}.json")
      file_name = File.join(@proc_dir, key)
      files << [key, ext2ctype('json'), file_name]
      ensure_dir_exists(File.join(@proc_dir, Sup::META_DIR))
      File.write(file_name, JSON.dump({
        width: width,
        height: height,
        preview_width: preview_width,
        preview_height: preview_height,
        content_type: ext2ctype(format),
        size: size,
        preview_size: preview_size,
        timestamp: Time.now.utc.to_s
      }))
    end

    # Save new image id as last id
    File.write(id_file, id)

    return {
      :files => files,
      :url => URI.join(@base_url, "#{id36}.#{format}").to_s
    }
  end

  # Converts file extension (w/o leading dot) to corresponding content type.
  def ext2ctype(ext)
    case ext
    when 'jpg', 'jpeg'
      'image/jpeg'
    when 'png'
      'image/png'
    when 'json'
      'application/json'
    else
      nil
    end
  end

  # Uploads a file to S3 bucket with specified key.
  def upload(key, file_name, content_type=nil)
    content_type ||= ext2ctype(key)
    type = content_type ? "as #{content_type}" : '(content type undefined)'
    logger.info "uploading s3://#{@bucket_name}/#{key} #{type}"
    @bucket.objects[key].write(
      :file => Pathname.new(file_name), 
      :content_type => content_type
    )
  end

  # Watch source directory for new image files.
  def watch!
    raise 'Initialization required' if @path.nil? or @bucket.nil?
    callback = Proc.new do |modified, added, removed|
      urls = []
      modified.each do |file_name|
        next if file_name.start_with?(@proc_dir)
        logger.info "new file: #{file_name}"
        info = process_image(file_name)
        info[:files].each do |file_info|
          key, content_type, file_name = file_info
          upload(key, file_name, content_type)
        end
        urls << info[:url]
      end
      unless urls.empty?
        Clipboard.copy urls.join("\n")
        if @args[:notify]
          title = urls.length > 1 ?
            "#{urls.length} files uploaded" : "File uploaded"
          notify(title, urls.join("\n"))
        end
      end
    end
    Listen.to(@path,
              only: Regexp.new("(\\.%s)$" % Sup::LEGAL_EXTENSIONS.join('|')),
              latency: @args.latency,
              force_polling: @args.force_polling,
              &callback).start

    logger.info "watching #{@path} (use Ctrl-C to exit)"
    trap("INT") {exit}
    sleep
  end
end

class CLI < Thor
  include Sup
  include Graphics

  package_name File.basename(__FILE__, '.*')

  class_option :log,
               :default => nil,
               :desc => 'File name to save log output'

  class_option :verbose,
               :type => :boolean,
               :desc => 'Verbose logging'

  desc 'watch <path> <bucket>',
       'Watch for new screenshots'
  long_desc 'Watch <path> for new screenshots ' +
       'and upload them to s3://<bucket>'
  option :proc_dir,
         :banner => '<path>',
         :default => Sup::PROC_DIR,
         :desc => 'Directory to save processed screenshots'

  option :latency,
         :type => :numeric,
         :default => Sup::DEFAULT_LATENCY,
         :desc => 'Callback latency in seconds'

  option :force_polling,
         :type => :boolean,
         :default => false,
         :desc => 'Use directory polling for new files'

  option :base_url,
         :default => Sup::BASE_URL,
         :desc => 'Base URL for uploaded files'

  option :quality,
         :type => :numeric,
         :default => Graphics::DEFAULT_JPEG_QUALITY,
         :desc => 'Quality for JPEG files'

  option :max_width,
         :type => :numeric,
         :default => Graphics::PREVIEW_MAX_WIDTH,
         :desc => 'Maximum preview width'

  option :max_height,
         :type => :numeric,
         :default => Graphics::PREVIEW_MAX_HEIGHT,
         :desc => 'Maximum preview height'

  option :preview,
         :type => :boolean,
         :default => false,
         :desc => 'Generate downscaled preview images'

  option :meta,
         :type => :boolean,
         :default => false,
         :desc => 'Save image metadata to JSON files'

  option :notify,
         :type => :boolean,
         :default => false,
         :desc => 'Notify user with popups'

  def watch(path, bucket)
    init(path, bucket, options)
    watch!
  end
end

CLI.start(ARGV)
