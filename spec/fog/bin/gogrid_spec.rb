require "minitest/autorun"
require "fog"
require "fog/bin"
require "helpers/bin"

describe GoGrid do
  include Fog::BinSpec

  let(:subject) { GoGrid }
end
