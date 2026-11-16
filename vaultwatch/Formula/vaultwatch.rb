class Vaultwatch < Formula
  desc "Guard an open securetrash vault on macOS (Spotlight/Time Machine/cloud)"
  homepage "https://github.com/Di-kairos/paranoid-tools"
  url "https://github.com/Di-kairos/paranoid-tools/archive/refs/tags/vaultwatch-v0.1.19.tar.gz"
  sha256 "9aadef730751282e233d5303d6e34ccee39d92b5029aa4a7fbefa31ca60aea33"
  license "MIT"

  def install
    bin.install "vaultwatch/vaultwatch"
  end

  test do
    assert_match "vaultwatch", shell_output("#{bin}/vaultwatch version")
  end
end
