class Vaultwatch < Formula
  desc "Guard an open securetrash vault on macOS (Spotlight/Time Machine/cloud)"
  homepage "https://github.com/Di-kairos/vaultwatch"
  url "https://github.com/Di-kairos/vaultwatch/archive/refs/tags/v0.1.7.tar.gz"
  sha256 "5a8611edbe84e0dea1bc14b5ceb3368296adf75f39c2ca6c72f64db6dea5e6de"
  license "MIT"

  def install
    bin.install "vaultwatch"
  end

  test do
    assert_match "vaultwatch", shell_output("#{bin}/vaultwatch version")
  end
end
