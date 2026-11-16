class Securetrash < Formula
  desc "Honest secure file deletion for macOS (FileVault + crypto-shred vaults)"
  homepage "https://github.com/Di-kairos/paranoid-tools"
  url "https://github.com/Di-kairos/paranoid-tools/archive/refs/tags/securetrash-v0.5.12.tar.gz"
  sha256 "7c6e827635061a540bc8dca38eeb7c45d27ba67f8fc001c3158fead168d50c26"
  license "MIT"

  def install
    bin.install "securetrash/securetrash"
  end

  test do
    assert_match "securetrash", shell_output("#{bin}/securetrash version")
  end
end
