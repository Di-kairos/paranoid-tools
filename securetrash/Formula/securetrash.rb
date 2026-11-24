class Securetrash < Formula
  desc "Honest secure file deletion for macOS (FileVault + crypto-shred vaults)"
  homepage "https://github.com/Di-kairos/paranoid-tools"
  url "https://github.com/Di-kairos/paranoid-tools/archive/refs/tags/securetrash-v0.5.13.tar.gz"
  sha256 "2d04652ca46dbf8f0e931e2e129e05d672acc3067b1f31566120913d395891cb"
  license "MIT"

  def install
    bin.install "securetrash/securetrash"
  end

  test do
    assert_match "securetrash", shell_output("#{bin}/securetrash version")
  end
end
