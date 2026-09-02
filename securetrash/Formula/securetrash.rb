class Securetrash < Formula
  desc "Honest secure file deletion for macOS (FileVault + crypto-shred vaults)"
  homepage "https://github.com/Di-kairos/paranoid-tools"
  url "https://github.com/Di-kairos/paranoid-tools/archive/refs/tags/securetrash-v0.5.8.tar.gz"
  sha256 "e6e7d645ee021adbd1f075a057d4c9a9b9af69515f7c36f5a854eef22ff7d5fd"
  license "MIT"

  def install
    bin.install "securetrash/securetrash"
  end

  test do
    assert_match "securetrash", shell_output("#{bin}/securetrash version")
  end
end
