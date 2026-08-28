class Vaultwatch < Formula
  desc "Guard an open securetrash vault on macOS (Spotlight/Time Machine/cloud)"
  homepage "https://github.com/Di-kairos/paranoid-tools"
  url "https://github.com/Di-kairos/paranoid-tools/archive/refs/tags/vaultwatch-v0.1.15.tar.gz"
  sha256 "d77640f107ffc2240c3edd08f4122b416fea0413d60f2bd5548f198780079fc1"
  license "MIT"

  def install
    bin.install "vaultwatch/vaultwatch"
  end

  test do
    assert_match "vaultwatch", shell_output("#{bin}/vaultwatch version")
  end
end
