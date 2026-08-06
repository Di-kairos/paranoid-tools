class Vaultwatch < Formula
  desc "Guard an open securetrash vault on macOS (Spotlight/Time Machine/cloud)"
  homepage "https://github.com/Di-kairos/vaultwatch"
  url "https://github.com/Di-kairos/vaultwatch/archive/refs/tags/v0.1.11.tar.gz"
  sha256 "ac8110b31657825b8cbd4a7e12778d3e735eb6b4bb9f65cdf04f8d837a479982"
  license "MIT"

  def install
    bin.install "vaultwatch"
  end

  test do
    assert_match "vaultwatch", shell_output("#{bin}/vaultwatch version")
  end
end
