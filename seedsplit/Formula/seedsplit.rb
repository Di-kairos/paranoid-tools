class Seedsplit < Formula
  desc "Split a secret into Shamir shares (pure Bash, GF(256))"
  homepage "https://github.com/Di-kairos/paranoid-tools"
  url "https://github.com/Di-kairos/paranoid-tools/archive/refs/tags/seedsplit-v0.5.6.tar.gz"
  sha256 "3364beb65f27f95fb0a0056ad6871c059c5a3e2891c397bbab510a17205f3de3"
  license "MIT"

  def install
    bin.install "seedsplit/seedsplit"
  end

  test do
    assert_match "seedsplit", shell_output("#{bin}/seedsplit version")
  end
end
