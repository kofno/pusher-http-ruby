require File.expand_path('../spec_helper', __FILE__)

describe Authentication do
  before :each do
    Time.stub!(:now).and_return(Time.at(1234))

    @token = Authentication::Token.new('key', 'secret')

    @request = Authentication::Request.new('/some/path', {
      "query" => "params",
      "go" => "here"
    })
    @signature = @request.sign(@token)[:auth_signature]
  end

  it "should generate base64 encoded signature from correct key" do
    @request.send(:string_to_sign).should == "/some/path\nauth_key=key&auth_timestamp=1234&go=here&query=params"
    @signature.should == 'i6+C/D+k/nUyLyPRlPRj6e32wLnIWRYXUsohTwImXws='
  end

  it "should make auth_hash available after request is signed" do
    request = Authentication::Request.new('/some/path', {
      "query" => "params"
    })
    lambda {
      request.auth_hash
    }.should raise_error('Request not signed')

    request.sign(@token)
    request.auth_hash.should == {
      :auth_signature => "QTtvm7KU6hF6esTvWm/0IPft1KdwI2VJ2n8MedYjfNA=",
      :auth_key => "key",
      :auth_timestamp => 1234
    }
  end

  it "should cope with symbol keys" do
    @request.query_hash = {
      :query => "params",
      :go => "here"
    }
    @request.sign(@token)[:auth_signature].should == @signature
  end

  it "should cope with upcase keys (keys are lowercased before signing)" do
    @request.query_hash = {
      "Query" => "params",
      "GO" => "here"
    }
    @request.sign(@token)[:auth_signature].should == @signature
  end

  it "should use the path to generate signature" do
    @request.path = '/some/other/path'
    @request.sign(@token)[:auth_signature].should_not == @signature
  end

  it "should use the query string keys to generate signature" do
    @request.query_hash = {
      "other" => "query"
    }
    @request.sign(@token)[:auth_signature].should_not == @signature
  end

  it "should use the query string values to generate signature" do
    @request.query_hash = {
      "key" => "notfoo",
      "other" => 'bar'
    }
    @request.sign(@token)[:signature].should_not == @signature
  end

  it "should also hash the body if included" do
    @request.body = 'some body text'
    @request.send(:string_to_sign).should == "/some/path\nauth_key=key&auth_timestamp=1234&go=here&query=params\nsome body text"
    @request.sign(@token)[:signature].should_not == @signature
  end

  describe "verification" do
    before :each do
      Time.stub!(:now).and_return(Time.at(1234))
      @request.sign(@token)
      @params = @request.query_hash.merge(@request.auth_hash)
    end

    it "should verify requests" do
      request = Authentication::Request.new('/some/path', @params)
      request.authenticate(@token).should == true
    end

    it "should raise error if signature is not correct" do
      @params[:auth_signature] =  'asdf'
      request = Authentication::Request.new('/some/path', @params)
      lambda {
        request.authenticate!(@token)
      }.should raise_error('Signature does not match: String to sign is "/some/path\nauth_key=key&auth_timestamp=1234&go=here&query=params"')
    end

    it "should raise error if timestamp not available" do
      @params.delete(:auth_timestamp)
      request = Authentication::Request.new('/some/path', @params)
      lambda {
        request.authenticate!(@token)
      }.should raise_error('Timestamp required')
    end

    it "should raise error if timestamp has expired (default of 600s)" do
      request = Authentication::Request.new('/some/path', @params)
      Time.stub!(:now).and_return(Time.at(1234 + 599))
      request.authenticate!(@token).should == true
      Time.stub!(:now).and_return(Time.at(1234 - 599))
      request.authenticate!(@token).should == true
      Time.stub!(:now).and_return(Time.at(1234 + 600))
      lambda {
        request.authenticate!(@token)
      }.should raise_error("Timestamp expired: Given timestamp (1970-01-01T00:20:34Z) not within 600s of server time (1970-01-01T00:30:34Z)")
      Time.stub!(:now).and_return(Time.at(1234 - 600))
      lambda {
        request.authenticate!(@token)
      }.should raise_error("Timestamp expired: Given timestamp (1970-01-01T00:20:34Z) not within 600s of server time (1970-01-01T00:10:34Z)")
    end

    it "should be possible to customize the timeout grace period" do
      grace = 10
      request = Authentication::Request.new('/some/path', @params)
      Time.stub!(:now).and_return(Time.at(1234 + grace - 1))
      request.authenticate!(@token, grace).should == true
      Time.stub!(:now).and_return(Time.at(1234 + grace))
      lambda {
        request.authenticate!(@token, grace)
      }.should raise_error("Timestamp expired: Given timestamp (1970-01-01T00:20:34Z) not within 10s of server time (1970-01-01T00:20:44Z)")
    end

    it "should be possible to skip timestamp check by passing nil" do
      request = Authentication::Request.new('/some/path', @params)
      Time.stub!(:now).and_return(Time.at(1234 + 1000))
      request.authenticate!(@token, nil).should == true
    end
  end
end
