class Vaultwatch < Formula
  desc "Guard an open securetrash vault on macOS (Spotlight/Time Machine/cloud)"
  homepage "https://github.com/Di-kairos/vaultwatch"
  url "https://github.com/Di-kairos/vaultwatch/archive/refs/tags/v0.1.13.tar.gz"
  sha256 "8a50fa81be965d8a2954fc43cceac8f0bc484c645c7ff28ac6e3056c83134d0b"
  license "MIT"

  def install
    bin.install "vaultwatch"
  end

  test do
    assert_match "vaultwatch", shell_output("#{bin}/vaultwatch version")
  end
end
