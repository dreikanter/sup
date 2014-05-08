require 'aws-sdk'
require 'clipboard'
require 'fileutils'
require 'json'
require 'listen'
require 'logger'
require 'uri'

# Configuration

SOURCE_PATH = File.expand_path 'D:\\Screenshots'
PROC_PATH = File.join SOURCE_PATH, 'Processed'
LATENCY = 0.5
FORCE_POLLING = false
S3_BUCKET = 'sh.drafts.cc'
BASE_URL = "http://#{S3_BUCKET}/"
LOG_NAME = nil
VERBOSE = false
JPEG_QUALITY = 80
IMAGEMAGICK_PATH = File.expand_path 'C:\\ImageMagick'

# Constants

ID_KEY = 'id.txt'
ID_FILE = File.join SOURCE_PATH, ID_KEY
LEGAL_EXTENSIONS = ['png', 'jpg', 'jpeg']
META_PREFIX = 'meta'
CONFIG = '.sup'

def init()
  $log = get_logger()
  $bucket = get_s3_bucket(S3_BUCKET)
  FileUtils.mkdir_p(PROC_PATH) unless File.directory? PROC_PATH
  meta_path = File.join PROC_PATH, META_PREFIX
  FileUtils.mkdir_p(meta_path) unless File.directory? meta_path
  $log.info "last id is #{get_last_id()}"
end

def get_logger()
  log_stream = if LOG_NAME then File.open(LOG_NAME, "a") else STDOUT end
  log = Logger.new log_stream
  log.level = if VERBOSE then Logger::WARN else Logger::INFO end
  log.datetime_format = '%Y-%m-%d %H:%M:%S'
  log.formatter = proc do |severity, datetime, progname, msg|
    "#{datetime.strftime($log.datetime_format)} #{severity}: #{msg}\n"
  end
  return log
end

def get_s3_bucket(bucket_name)
  config_file = File.join Dir.home, CONFIG
  options = Hash[*File.read(config_file).split(/[= \n]+/)]
  s3 = AWS::S3.new(
    access_key_id: options['access_key_id'],
    secret_access_key: options['secret_access_key'],
    s3_endpoint: options['s3_endpoint']
  )
  return s3.buckets[bucket_name]
end

# Returns current cached ID.
def get_last_id()
  begin
    return Integer(File.read(ID_FILE))
  rescue => e
    $log.debug "error reading id file: #{e}"
    last_id = pull_last_id()
    File.write(ID_FILE, last_id)
    return last_id
  end
end

def pull_last_id()
  $log.info "scanning s3://#{S3_BUCKET} for last id"
  last_id = 0
  begin
    objects = $bucket.objects.with_prefix("#{META_PREFIX}/")
    return (objects.map {|o| File.basename(o.key, '.*').to_i}).max || 0
  rescue => e
    $log.error "error scanning for the last image id: #{e}"
    exit
  end
end

def jpgpng(extension)
  extension == '.png' ? '.jpg' : '.png'
end

# Converts image file to optimal format, generate metadata file,
# and returns an array of generated file names.
def process_image(src_file)
  ext = File.extname(src_file).downcase
  unless LEGAL_EXTENSIONS.include? ext[1..-1]
    log.error "unsupported format: #{src_file}"
    return {}
  end
  ext = '.jpg' if ext == '.jpeg'

  id = get_last_id() + 1
  $log.info "new image id: #{id}"

  dst_file = File.join PROC_PATH, [id, jpgpng(ext)].join
  options = ext == '.png' ? "-quality #{JPEG_QUALITY}" : ''
  convert_cmd = IMAGEMAGICK_PATH.nil? || IMAGEMAGICK_PATH.empty? ?
    'convert' : File.join(IMAGEMAGICK_PATH, 'convert')
  cmd = "#{convert_cmd} #{options} \"#{src_file}\" \"#{dst_file}\""
  $log.debug "#{cmd}"
  unless system(cmd)
    $log.error "error converting source image"
    return nil
  end

  src_size = File.size(src_file)
  dst_size = File.size(dst_file)
  if src_size <= dst_size
    File.unlink(dst_file)
    dst_file = File.join PROC_PATH, [id, ext].join
    FileUtils.copy_file src_file, dst_file
  end
  short_name = File.basename dst_file
  generated = {short_name => dst_file}
  url = URI.join(BASE_URL, short_name).to_s

  format = File.extname(dst_file).upcase[1..-1]
  max_size = [dst_size, src_size].max
  gain = (Float(dst_size - src_size).abs / max_size * 100).round(1)
  $log.info "#{format} is #{gain}% more compact"

  meta_key = File.join META_PREFIX, "#{id}.json"
  meta_file = File.join PROC_PATH, meta_key
  File.write meta_file, JSON.dump({
    width: 0,
    height: 0,
    format: format,
    timestamp: ''
  })
  generated[meta_key] = meta_file

  # Save new image id as last id
  File.write ID_FILE, id
  return url, generated
end

# Uploads a file to S3 bucket with specified key.
def upload_file(file_name, key)
  src_file = File.basename file_name
  $log.info "uploading s3://#{S3_BUCKET}/#{key}"
  $bucket.objects[key].write(Pathname.new file_name)
end

def notify(title, message)
  cmd = "notifu /p \"#{title}\" /m \"#{message}\" /d 2000 /t info /q"
  system(cmd)
end

init

callback = Proc.new do |modified, added, removed|
  modified.each do |file_name|
    next if file_name.start_with? PROC_PATH
    $log.info "new file: #{file_name}"
    url, generated = process_image(file_name)
    generated.each do |key, name|
      upload_file(name, key)
    end
    notify "Screenshot Uploader", "URL: #{url}"
    Clipboard.copy url
  end
end

$log.info "start watching #{SOURCE_PATH}"

Listen.to(SOURCE_PATH,
          only: Regexp.new("(\\.%s)$" % LEGAL_EXTENSIONS.join('|')),
          latency: LATENCY,
          force_polling: FORCE_POLLING,
          &callback).start

sleep
