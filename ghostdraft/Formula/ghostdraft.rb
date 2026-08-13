class Ghostdraft < Formula
  desc "Ephemeral scratch draft on macOS, kept in a RAM disk not on-disk temp"
  homepage "https://github.com/Di-kairos/ghostdraft"
  url "https://github.com/Di-kairos/ghostdraft/archive/refs/tags/v0.1.18.tar.gz"
  sha256 "00698a98899715c8897eca780859b0791c977be5023fb9de543cdaa742cc0114"
  license "MIT"

  def install
    bin.install "ghostdraft"
  end

  test do
    assert_match "ghostdraft", shell_output("#{bin}/ghostdraft version")
  end
end
