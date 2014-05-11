# Sup — Screenshot Uploader

This is a tiny companion service for your favorite screenshot tool, allowing you to take control over image sharing functionality.

Sup is compatible with any screenshot capturer that is able to save screenshots to file system. Here are some options:

- [Monosnap](http://monosnap.com)
- [FastStone Capture](http://www.faststone.org/FSCaptureDetail.htm)
- [Snipping Tool](http://windows.microsoft.com/en-us/windows7/products/features/snipping-tool)
- [Cropper](https://cropper.codeplex.com/)
- [Lightscreen](http://lightscreen.com.ar/)

Sup monitors a directory where screenshots supposed to be saved, and performs the following operations for each new file:

- Determine better graphic format from JPEG and PNG, and convert source file if needed.
- Give a short unique name to the screenshot.
- (Optionally) Generate downscaled preview image with required dimensions.
- (Optionally) Save image metadata (like width, height, timestamp and some other information) to a JSON file.
- Upload everything to S3 bucket.
- Copy new screenshot URL to clipboard.
- Notify user with popup.

## Installation

Sup requires [ImageMagick](http://imagemagick.org/) to be installed and available on PATH. This instruction also assumes you already have git, Ruby and bundle.

Clone the sources from GitHub and install script dependencies:

	git clone https://github.com/dreikanter/sup.git
	cd sup
	bundle

To access S3 bucket sup requires Amazon Web Services [access credentials](https://console.aws.amazon.com/iam/home?#users) to be saved at `.sup` file in user's home directory (`~/.sup` on OS X and Linux, or `%userprofile%/.sup` on Windows). Here is an example:

	access_key_id = ABCDEFGHIKLMNOPQRSTU
	secret_access_key = 1278616238946awjgfjqgafe36451876fghqwrgg
	s3_endpoint = s3-eu-west-1.amazonaws.com

User notification is working on OS X and Window. Sup uses standard system notification on OS X. On Windows you will need a helper tool [notifu](http://www.paralint.com/projects/notifu/) to be available on `%PATH%`.

<p align="center"><img src="https://s3-eu-west-1.amazonaws.com/sh.drafts.cc/2w.jpg" alt="sup notification" /></p>

## Usage

This is a basic command to watch for new screenshots at `~/Screenshots` and upload them to Amazon S3 bucket named `shots.example.com`:

	ruby sup.rb watch ~/Screenshots shots.example.com --notify

In this example `--notify` option enables user notification. Use `--help` for other usage details.

## Development

Setting up [fakes3](https://github.com/jubos/fake-s3) — Amazon S3 emulator for local testing:

	fakes3 --root /mnt/sup_test_bucket --port 10001

On Windows:

	fakes3 --root D:\tmp\sup_test_bucket --port 10001
