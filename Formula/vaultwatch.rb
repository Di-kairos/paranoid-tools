class Vaultwatch < Formula
  desc "Guard an open securetrash vault on macOS (Spotlight/Time Machine/cloud)"
  homepage "https://github.com/Di-kairos/vaultwatch"
  url "https://github.com/Di-kairos/vaultwatch/archive/refs/tags/v0.1.9.tar.gz"
  sha256 "b0ceac7096877c962ecbe3dbf9407ddacd0e931457785f02042e2709bf57994a"
  license "MIT"

  def install
    bin.install "vaultwatch"
  end

  test do
    assert_match "vaultwatch", shell_output("#{bin}/vaultwatch version")
  end
end
