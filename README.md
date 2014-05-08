# SUP!

SUP is an acronym standing for Screenshot UPloader. It is a companion service for your favorite screenshot capturer, like [Monosnap](http://monosnap.com), [FastStone Capture](http://www.faststone.org/FSCaptureDetail.htm), or any other tool able to save screenshots to file system. SUP monitors a directory where new screenshots supposed to be saved, and performs the following operations for each one of them:

- Determine better graphic format (JPEG or PNG), and convert source file if needed.
- Rename the screenshot to a short unique name.
- Upload everything to the S3 bucket.
- Copy screenshot URL to clipboard.
- Notify user using visual notification.

## Usage

	bundle exec ruby sup.rb

## Development

Setting up [fakes3](https://github.com/jubos/fake-s3) — Amazon S3 emulator for local testing:

	fakes3 --root /mnt/sup_test_bucket --port 10001

On Windows:

	fakes3 --root D:\tmp\sup_test_bucket --port 10001
