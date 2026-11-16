class Seedsplit < Formula
  desc "Split a secret into Shamir shares (pure Bash, GF(256))"
  homepage "https://github.com/Di-kairos/paranoid-tools"
  url "https://github.com/Di-kairos/paranoid-tools/archive/refs/tags/seedsplit-v0.5.10.tar.gz"
  sha256 "7001405f712e82c7cf53417920417eeba9423258c9d33b1c47f9453c327bd7d8"
  license "MIT"

  def install
    bin.install "seedsplit/seedsplit"
  end

  test do
    assert_match "seedsplit", shell_output("#{bin}/seedsplit version")
  end
end
