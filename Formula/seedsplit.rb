class Seedsplit < Formula
  desc "Split a secret into Shamir shares (pure Bash, GF(256))"
  homepage "https://github.com/Di-kairos/seedsplit"
  url "https://github.com/Di-kairos/seedsplit/archive/refs/tags/v0.5.4.tar.gz"
  sha256 "4d79ef0fe1e825730644e2deee5e53ea9f8abe50b00349559efa0e565d7a0bac"
  license "MIT"

  def install
    bin.install "seedsplit"
  end

  test do
    assert_match "seedsplit", shell_output("#{bin}/seedsplit version")
  end
end
