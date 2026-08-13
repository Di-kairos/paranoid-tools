class Seedsplit < Formula
  desc "Split a secret into Shamir shares (pure Bash, GF(256))"
  homepage "https://github.com/Di-kairos/seedsplit"
  url "https://github.com/Di-kairos/seedsplit/archive/refs/tags/v0.5.5.tar.gz"
  sha256 "ad733a66eb0ad963b974f9f671d48b4eb0df985b760b98b4192f4b0583107353"
  license "MIT"

  def install
    bin.install "seedsplit"
  end

  test do
    assert_match "seedsplit", shell_output("#{bin}/seedsplit version")
  end
end
