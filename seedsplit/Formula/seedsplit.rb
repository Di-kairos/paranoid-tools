class Seedsplit < Formula
  desc "Split a secret into Shamir shares (pure Bash, GF(256))"
  homepage "https://github.com/Di-kairos/paranoid-tools"
  url "https://github.com/Di-kairos/paranoid-tools/archive/refs/tags/seedsplit-v0.5.9.tar.gz"
  sha256 "158336486802bdc19a0172adbc9271a856ca3e1545aa178b6dddd07cd2d5a6c5"
  license "MIT"

  def install
    bin.install "seedsplit/seedsplit"
  end

  test do
    assert_match "seedsplit", shell_output("#{bin}/seedsplit version")
  end
end
