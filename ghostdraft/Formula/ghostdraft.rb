class Ghostdraft < Formula
  desc "Ephemeral scratch draft on macOS, kept in a RAM disk not on-disk temp"
  homepage "https://github.com/Di-kairos/paranoid-tools"
  url "https://github.com/Di-kairos/paranoid-tools/archive/refs/tags/ghostdraft-v0.1.22.tar.gz"
  sha256 "02143a1802556e9efcacd8cf698fe4e030072bdcf69b778515961ec490657eca"
  license "MIT"

  def install
    bin.install "ghostdraft/ghostdraft"
  end

  test do
    assert_match "ghostdraft", shell_output("#{bin}/ghostdraft version")
  end
end
