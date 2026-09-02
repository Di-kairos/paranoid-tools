class Ghostdraft < Formula
  desc "Ephemeral scratch draft on macOS, kept in a RAM disk not on-disk temp"
  homepage "https://github.com/Di-kairos/paranoid-tools"
  url "https://github.com/Di-kairos/paranoid-tools/archive/refs/tags/ghostdraft-v0.1.20.tar.gz"
  sha256 "c2ccd225cfc215ddd846993265a3c7790a212a78a0c36c8990c1361e6defb6c5"
  license "MIT"

  def install
    bin.install "ghostdraft/ghostdraft"
  end

  test do
    assert_match "ghostdraft", shell_output("#{bin}/ghostdraft version")
  end
end
