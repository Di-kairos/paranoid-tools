class Ghostdraft < Formula
  desc "Ephemeral scratch draft on macOS, kept in a RAM disk not on-disk temp"
  homepage "https://github.com/Di-kairos/paranoid-tools"
  url "https://github.com/Di-kairos/paranoid-tools/archive/refs/tags/ghostdraft-v0.1.19.tar.gz"
  sha256 "a469cc2bf6800b2663d0acfcac6e0c9fae48fbcc5c3e976746af38455d18352b"
  license "MIT"

  def install
    bin.install "ghostdraft/ghostdraft"
  end

  test do
    assert_match "ghostdraft", shell_output("#{bin}/ghostdraft version")
  end
end
