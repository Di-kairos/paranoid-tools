class Seedsplit < Formula
  desc "Split a secret into Shamir shares (pure Bash, GF(256))"
  homepage "https://github.com/Di-kairos/seedsplit"
  url "https://github.com/Di-kairos/seedsplit/archive/refs/tags/v0.5.2.tar.gz"
  sha256 "b0e782b42b2a4cfd7fc11501a2371332a52d3d668780f0a2373fe6ce35a8332b"
  license "MIT"

  def install
    bin.install "seedsplit"
  end

  test do
    assert_match "seedsplit", shell_output("#{bin}/seedsplit version")
  end
end
