# Sup — Screenshot Uploader

This is a tiny companion service to your favorite screenshot tool. It allows to take control over image sharing functionality. Sup is compatible with any application that can save a screenshot to file. Here are some examples:

- [Monosnap](http://monosnap.com)
- [FastStone Capture](http://www.faststone.org/FSCaptureDetail.htm)
- [Snipping Tool](http://windows.microsoft.com/en-us/windows7/products/features/snipping-tool)
- [Cropper](https://cropper.codeplex.com/)
- [Lightscreen](http://lightscreen.com.ar/)

Sup monitors file system for new screenshots and carries out these steps for each new image:

- Determine most compact graphic format from JPEG and PNG, and convert source file if needed.
- Give a short unique name to the screenshot.
- Generate downscaled preview image with user-defined dimensions.
- Save image metadata, like width, height, timestamp and some other details, to a JSON file.
- Upload everything to S3 bucket.
- Copy direct screenshot URL to clipboard.
- Notify user with popup.

## Installation

Sup requires [ImageMagick](http://imagemagick.org/) to be installed and available on PATH. Also this instruction assumes you already have git, Ruby and bundle.

Clone the sources from GitHub and install script dependencies:

	git clone https://github.com/dreikanter/sup.git
	cd sup
	bundle

To access S3 bucket sup requires Amazon Web Services [access credentials](https://console.aws.amazon.com/iam/home?#users) to be saved at `.sup` file in user's home directory (`~/.sup` on OS X and Linux, or `%userprofile%/.sup` on Windows). Here is an example:

	access_key_id = ABCDEFGHIKLMNOPQRSTU
	secret_access_key = 1278616238946awjgfjqgafe36451876fghqwrgg
	s3_endpoint = s3-eu-west-1.amazonaws.com

User notification is working on OS X and Window. Sup uses standard system notification on OS X. On Windows you will need a helper tool [notifu](http://www.paralint.com/projects/notifu/) to be available on `%PATH%`.

![](http://sh.drafts.cc/2w.jpg)

## Usage

This is a basic command to watch for new screenshots at `~/Screenshots` and upload them to Amazon S3 bucket named `shots.example.com`:

	ruby sup.rb watch ~/Screenshots shots.example.com --notify

In this example `--notify` option enables user notification. Use `--help` for other usage details.

## Development

Setting up [fakes3](https://github.com/jubos/fake-s3) — Amazon S3 emulator for local testing:

	fakes3 --root /mnt/sup_test_bucket --port 10001

On Windows:

	fakes3 --root D:\tmp\sup_test_bucket --port 10001
