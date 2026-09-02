class Vaultwatch < Formula
  desc "Guard an open securetrash vault on macOS (Spotlight/Time Machine/cloud)"
  homepage "https://github.com/Di-kairos/paranoid-tools"
  url "https://github.com/Di-kairos/paranoid-tools/archive/refs/tags/vaultwatch-v0.1.16.tar.gz"
  sha256 "8d90498ebd0751d2655609a5c869a32c9c31c9a3a895d1909a1bb0864f949ec2"
  license "MIT"

  def install
    bin.install "vaultwatch/vaultwatch"
  end

  test do
    assert_match "vaultwatch", shell_output("#{bin}/vaultwatch version")
  end
end
