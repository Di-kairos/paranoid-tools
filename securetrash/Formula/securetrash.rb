class Securetrash < Formula
  desc "Honest secure file deletion for macOS (FileVault + crypto-shred vaults)"
  homepage "https://github.com/Di-kairos/paranoid-tools"
  url "https://github.com/Di-kairos/paranoid-tools/archive/refs/tags/securetrash-v0.5.10.tar.gz"
  sha256 "d7300b060d080232b950c19dfef6975cc4c0fb22909d4485406aa8f51af5a709"
  license "MIT"

  def install
    bin.install "securetrash/securetrash"
  end

  test do
    assert_match "securetrash", shell_output("#{bin}/securetrash version")
  end
end
