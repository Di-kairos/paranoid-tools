class Seedsplit < Formula
  desc "Split a secret into Shamir shares (pure Bash, GF(256))"
  homepage "https://github.com/Di-kairos/seedsplit"
  url "https://github.com/Di-kairos/seedsplit/archive/refs/tags/v0.5.1.tar.gz"
  sha256 "f4665488845820e117243536f94be26e5364af0b4424b745cd6650fbfe91424a"
  license "MIT"

  def install
    bin.install "seedsplit"
  end

  test do
    assert_match "seedsplit", shell_output("#{bin}/seedsplit version")
  end
end
