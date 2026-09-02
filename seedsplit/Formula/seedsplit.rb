class Seedsplit < Formula
  desc "Split a secret into Shamir shares (pure Bash, GF(256))"
  homepage "https://github.com/Di-kairos/paranoid-tools"
  url "https://github.com/Di-kairos/paranoid-tools/archive/refs/tags/seedsplit-v0.5.7.tar.gz"
  sha256 "bd68455626609eafa7b9d1a0e0c493e0cf49ad1069a92c73204f40cd129a6a73"
  license "MIT"

  def install
    bin.install "seedsplit/seedsplit"
  end

  test do
    assert_match "seedsplit", shell_output("#{bin}/seedsplit version")
  end
end
