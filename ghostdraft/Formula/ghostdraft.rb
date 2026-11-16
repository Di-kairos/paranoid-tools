class Ghostdraft < Formula
  desc "Ephemeral scratch draft on macOS, kept in a RAM disk not on-disk temp"
  homepage "https://github.com/Di-kairos/paranoid-tools"
  url "https://github.com/Di-kairos/paranoid-tools/archive/refs/tags/ghostdraft-v0.1.21.tar.gz"
  sha256 "d6a3f7b8358376738483537a8737d933ef634b32d842a2b0474343bd5f80e617"
  license "MIT"

  def install
    bin.install "ghostdraft/ghostdraft"
  end

  test do
    assert_match "ghostdraft", shell_output("#{bin}/ghostdraft version")
  end
end
