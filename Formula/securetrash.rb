class Securetrash < Formula
  desc "Honest secure file deletion for macOS (FileVault + crypto-shred vaults)"
  homepage "https://github.com/Di-kairos/securetrash"
  url "https://github.com/Di-kairos/securetrash/archive/refs/tags/v0.5.2.tar.gz"
  sha256 "ffd2d12a9a16e51dbca7f6f6a0dbb0013c8339c27cbeda0b0ef63b8f31d61a5d"
  license "MIT"

  def install
    bin.install "securetrash"
  end

  test do
    assert_match "securetrash", shell_output("#{bin}/securetrash version")
  end
end
