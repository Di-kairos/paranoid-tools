class Securetrash < Formula
  desc "Honest secure file deletion for macOS (FileVault + crypto-shred vaults)"
  homepage "https://github.com/Di-kairos/paranoid-tools"
  url "https://github.com/Di-kairos/paranoid-tools/archive/refs/tags/securetrash-v0.5.7.tar.gz"
  sha256 "9927dfbe141dc95f76ec05830154211fa382d0f1440e1de0b39235aa374ff91e"
  license "MIT"

  def install
    bin.install "securetrash/securetrash"
  end

  test do
    assert_match "securetrash", shell_output("#{bin}/securetrash version")
  end
end
