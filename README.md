# SUP!

SUP is an acronym standing for Screenshot UPloader. It is a companion service for your favorite screenshot capturer, like [Monosnap](http://monosnap.com), [FastStone Capture](http://www.faststone.org/FSCaptureDetail.htm), or any other tool able to save screenshots to file system. SUP monitors a directory where new screenshots supposed to be saved, and performs the following operations for each one of them:

- Determine better graphic format (JPEG or PNG), and convert source file if needed.
- Rename the screenshot to a short unique name.
- Upload everything to the S3 bucket.
- Copy screenshot URL to clipboard.
- Notify user using visual notification.

## Usage

To access S3 buckets sup requires Amazon Web Services [access credentials](https://console.aws.amazon.com/iam/home?#users) to be saved at `.sup` file in user's home directory (`~/.sup` on OS X and Linux, or `%userprofile%/.sup` on Windows). Here is `.sup` file example:

	access_key_id = ABCDEFGHIKLMNOPQRSTU
	secret_access_key = 1278616238946awjgfjqgafe36451876fghqwrgg
	s3_endpoint = s3-eu-west-1.amazonaws.com

This is a basic command to watch for new screenshots at `~/Screenshots` and upload them to `s3://shots.example.com`:

	ruby sup.rb watch ~/Screenshots shots.example.com

Use `--help` for usage details.

## Development

Setting up [fakes3](https://github.com/jubos/fake-s3) — Amazon S3 emulator for local testing:

	fakes3 --root /mnt/sup_test_bucket --port 10001

On Windows:

	fakes3 --root D:\tmp\sup_test_bucket --port 10001
