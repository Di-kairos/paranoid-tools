class Vaultwatch < Formula
  desc "Guard an open securetrash vault on macOS (Spotlight/Time Machine/cloud)"
  homepage "https://github.com/Di-kairos/paranoid-tools"
  url "https://github.com/Di-kairos/paranoid-tools/archive/refs/tags/vaultwatch-v0.1.18.tar.gz"
  sha256 "b5eb500c8d8bbc84ce5097d81dacc01789aed6e56cb4bf8c3680d4a820dfb9b6"
  license "MIT"

  def install
    bin.install "vaultwatch/vaultwatch"
  end

  test do
    assert_match "vaultwatch", shell_output("#{bin}/vaultwatch version")
  end
end
