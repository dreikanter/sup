require 'aws-sdk'
require 'clipboard'
require 'fileutils'
require 'json'
require 'filesize'
require 'listen'
require 'logger'
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

module Sup
  include Logging

  # Constants
  META_DIR = 'meta'
  PROC_DIR = 'processed'
  ID_FILE = 'id.txt'
  CONFIG_FILE = File.join Dir.home, '.sup'
  LEGAL_EXTENSIONS = ['png', 'jpg']
  BAD_IDS = ['meta', 'fuck', 'bitch']

  # Defaults
  JPEG_QUALITY = 80
  BASE_URL = 'http://<bucket>/'

  # Initialize everything.
  def init(path, bucket_name, args)
    init_logger(args[:log_file], args[:verbose] == true)

    @path = path
    @proc_dir = args[:proc_dir]
    if Pathname.new(@proc_dir).relative?
      @proc_dir = File.expand_path(@proc_dir, @path)
    end
    FileUtils.mkdir_p(File.join(@proc_dir, Sup::META_DIR))

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

  # ImageMagick's convert.
  def convert(src_file, dst_file)
    use_path = @args.im_dir.nil? || args.im_dir.empty?
    cmd = use_path ? 'convert' : File.join(@args.im_dir, 'convert')
    to_jpg = '.jpg' == File.extname(dst_file)
    options = to_jpg ? "-quality #{@args[:jpeg_quality]}" : ''
    return execute("#{cmd} #{options} \"#{src_file}\" \"#{dst_file}\"")
  end

  # Notify user.
  def notify(title, message)
    # TODO: Variate notification methods
    cmd = "notifu /p \"#{title}\" /m \"#{message}\" /d 2000 /t info /q"
    execute(cmd)
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
    logger.info "new image id: #{id36} (id)"

    # Generating image copy in alternative format
    format = jpg_png(ext)
    dst_file = File.join(@proc_dir, "#{id36}.#{format}")
    unless convert(src_file, dst_file)
      logger.error "error converting source image"
      return nil
    end

    # Using most compact format
    src_size = File.size(src_file)
    dst_size = File.size(dst_file)
    if src_size <= dst_size
      File.unlink(dst_file)
      format = ext
      dst_file = File.join(@proc_dir, "#{id36}.#{format}")
      FileUtils.copy_file(src_file, dst_file)
    end
    max_size = [dst_size, src_size].max
    gain = (Float(dst_size - src_size).abs / max_size * 100).round(1)
    size = [dst_size, src_size].min
    logger.info "#{format.upcase} is #{gain}% more compact"
    pretty_size = Filesize.from("12502343 B").pretty
    logger.info "image size: #{pretty_size}"

    # Generate metadata file
    meta_key = File.join(Sup::META_DIR, "#{id36}.json")
    meta_file = File.join(@proc_dir, meta_key)
    File.write(meta_file, JSON.dump({
      width: 0,
      height: 0,
      format: format,
      size: size,
      timestamp: Time.now.utc.to_s
    }))

    # Save new image id as last id
    File.write(id_file, id)

    return {
      :key => "#{id36}.#{format}",
      :file => dst_file,
      :meta_key => meta_key,
      :meta_file => meta_file,
      :url => URI.join(@base_url, "#{id36}.#{format}").to_s
    }
  end

  # Uploads a file to S3 bucket with specified key.
  def upload(file_name, key)
    logger.info "uploading s3://#{@bucket_name}/#{key}"
    @bucket.objects[key].write(Pathname.new(file_name))
  end

  # Watch source directory for new image files.
  def watch!
    raise 'Initialization required' if @path.nil? or @bucket.nil?
    callback = Proc.new do |modified, added, removed|
      modified.each do |file_name|
        next if file_name.start_with?(@proc_dir)
        logger.info "new file: #{file_name}"
        info = process_image(file_name)
        upload(info[:file], info[:key])
        upload(info[:meta_file], info[:meta_key])
        Clipboard.copy info[:url]
        notify("Screenshot Uploader", "URL: #{info[:url]}")
      end
    end
    Listen.to(@path,
              only: Regexp.new("(\\.%s)$" % Sup::LEGAL_EXTENSIONS.join('|')),
              latency: @args.latency,
              force_polling: @args.force_polling,
              &callback).start
    logger.info "watching #{@path} (use Ctrl-C to exit)"
    sleep
  end
end

class CLI < Thor
  include Sup

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
  option :save,
         :type => :boolean,
         :default => false,
         :desc => 'Save local copy for processed files'

  option :proc_dir,
         :banner => '<path>',
         :default => Sup::PROC_DIR,
         :desc => 'Directory to save processed screenshots'

  option :latency,
         :type => :numeric,
         :default => 0.5,
         :desc => 'Callback latency in seconds'

  option :force_polling,
         :type => :boolean,
         :default => false,
         :desc => 'Use directory polling for new files'

  option :base_url,
         :default => Sup::BASE_URL,
         :desc => 'Base URL for uploaded files'

  option :jpeg_quality,
         :type => :numeric,
         :default => Sup::JPEG_QUALITY,
         :desc => 'Quality for JPEG files'

  option :im_dir,
         :banner => '<path>',
         :desc => 'Path to ImageMagick tools (depend on $path by default)'
  def watch(path, bucket)
    init(path, bucket, options)
    watch!
  end
end

CLI.start(ARGV)
