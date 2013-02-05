require 'spec_helper'
require 'yajl'
require 'rack'

module Palmade::PuppetMaster
  module Puppets::Mongrel2
    describe Request, 'parser' do
      let(:uuid)    { '92d9876e-d950-4e14-8177-3c785be3ed8e' }
      let(:conn_id) { '0' }
      it 'should include basic headers' do
        msg = '/ 128:{"PATH":"/","x-forwarded-for":"127.0.0.1","host":"bizsupport.local","METHOD":"GET","VERSION":"HTTP/1.1","URI":"/","PATTERN":"/"},0:, '
        request = Request.parse("#{uuid} #{conn_id} #{msg}", "chroot")
        request.env['SERVER_PROTOCOL'].should == 'HTTP/1.1'
        request.env['REQUEST_PATH'].should == '/'
        request.env['HTTP_VERSION'].should == 'HTTP/1.1'
        request.env['REQUEST_URI'].should == '/'
        request.env['GATEWAY_INTERFACE'].should == 'CGI/1.1'
        request.env['REQUEST_METHOD'].should == 'GET'
        request.env["rack.url_scheme"].should == 'http'
        request.env['FRAGMENT'].to_s.should be_empty
        request.env['QUERY_STRING'].to_s.should be_empty

        request.should validate_with_lint
      end

      it 'should not prepend HTTP_ to Content-Type and Content-Length' do
        msg = '/ 181:{"PATH":"/","x-forwarded-for":"127.0.0.1","content-type":"text/html","content-length":"2","host":"diabetescirkel.local","METHOD":"POST","VERSION":"HTTP/1.1","URI":"/","PATTERN":"/"},2:aa, '
        request = Request.parse("#{uuid} #{conn_id} #{msg}", "chroot")
        request.env.keys.should_not include('HTTP_CONTENT_TYPE', 'HTTP_CONTENT_LENGTH')
        request.env.keys.should include('CONTENT_TYPE', 'CONTENT_LENGTH')

        request.should validate_with_lint
      end

      it 'should support fragment in uri' do
        msg = '/forums/1/topics/2375 221:{"PATH":"/forums/1/topics/2375","x-forwarded-for":"127.0.0.1","host":"diabetescirkel.local","METHOD":"GET","VERSION":"HTTP/1.1","URI":"/forums/1/topics/2375?page=1","QUERY":"page=1","FRAGMENT":"posts-17408","PATTERN":"/"},0:, '
        request = Request.parse("#{uuid} #{conn_id} #{msg}", "chroot")

        request.env['REQUEST_URI'].should == '/forums/1/topics/2375?page=1'
        request.env['PATH_INFO'].should == '/forums/1/topics/2375'
        request.env['QUERY_STRING'].should == 'page=1'
        request.env['FRAGMENT'].should == 'posts-17408'

        request.should validate_with_lint
      end

      it 'should parse path with query string' do
        msg = '/index.html 176:{"PATH":"/index.html","x-forwarded-for":"127.0.0.1","host":"diabetescirkel.local","METHOD":"GET","VERSION":"HTTP/1.1","URI":"/index.html?234235","QUERY":"234235","PATTERN":"/"},0:, '
        request = Request.parse("#{uuid} #{conn_id} #{msg}", "chroot")
        request.env['REQUEST_PATH'].should == '/index.html'
        request.env['QUERY_STRING'].should == '234235'
        request.env['FRAGMENT'].should be_nil

        request.should validate_with_lint
      end

      it 'should parse headers from GET request' do
        msg = '/ 537:{"PATH":"/","keep-alive":"300","x-forwarded-for":"127.0.0.1","accept-language":"en-us,en;q=0.5","connection":"keep-alive","accept-encoding":"gzip,deflate","accept-charset":"ISO-8859-1,utf-8;q=0.7,*;q=0.7","accept":"text/xml,application/xml,application/xhtml+xml,text/html;q=0.9,text/plain;q=0.8,image/png,*/*;q=0.5","user-agent":"Mozilla/5.0 (Macintosh; U; Intel Mac OS X; en-US; rv:1.8.1.9) Gecko/20071025 Firefox/2.0.0.9","host":"diabetescirkel.local:3000","cookie":"mium=7","METHOD":"GET","VERSION":"HTTP/1.1","URI":"/","PATTERN":"/"},0:, '
        request = Request.parse("#{uuid} #{conn_id} #{msg}", "chroot")
        request.env['HTTP_HOST'].should == 'diabetescirkel.local:3000'
        request.env['SERVER_NAME'].should == 'diabetescirkel.local'
        request.env['SERVER_PORT'].should == '3000'
        request.env['HTTP_COOKIE'].should == 'mium=7'

        request.should validate_with_lint
      end

      it 'should parse POST request with data' do
        msg = '/postit 599:{"PATH":"/postit","keep-alive":"300","x-forwarded-for":"127.0.0.1","content-type":"text/html","accept-language":"en-us,en;q=0.5","connection":"keep-alive","accept-encoding":"gzip,deflate","content-length":"33","accept-charset":"ISO-8859-1,utf-8;q=0.7,*;q=0.7","accept":"text/xml,application/xml,application/xhtml+xml,text/html;q=0.9,text/plain;q=0.8,image/png,*/*;q=0.5","user-agent":"Mozilla/5.0 (Macintosh; U; Intel Mac OS X; en-US; rv:1.8.1.9) Gecko/20071025 Firefox/2.0.0.9","host":"diabetescirkel.local:3000","cookie":"mium=7","METHOD":"POST","VERSION":"HTTP/1.1","URI":"/postit","PATTERN":"/"},33:name=foo&email=bar@caresharing.eu, '
        request = Request.parse("#{uuid} #{conn_id} #{msg}", "chroot")
        request.env['REQUEST_METHOD'].should == 'POST'
        request.env['REQUEST_URI'].should == '/postit'
        request.env['CONTENT_TYPE'].should == 'text/html'
        request.env['CONTENT_LENGTH'].should == '33'
        request.env['HTTP_ACCEPT'].should == 'text/xml,application/xml,application/xhtml+xml,text/html;q=0.9,text/plain;q=0.8,image/png,*/*;q=0.5'
        request.env['HTTP_ACCEPT_LANGUAGE'].should == 'en-us,en;q=0.5'

        request.body.rewind
        request.body.read.should == 'name=foo&email=bar@caresharing.eu'
        request.body.class.should == StringIO

        request.should validate_with_lint
      end

      it 'should not fuck up on stupid fucked IE6 headers' do
        msg = '/codes/58-tracking-file-downloads-automatically-in-google-analytics-with-prototype/refactors 782:{"PATH":"/codes/58-tracking-file-downloads-automatically-in-google-analytics-with-prototype/refactors","x-forwarded-for":"127.0.0.1","range":"bytes=0-499999","content-type":"application/x-www-form-urlencoded","connection":"close","content-length":"1","x-real-ip":"62.24.71.95","referer":"http://refactormycode.com/codes/58-tracking-file-downloads-automatically-in-google-analytics-with-prototype","accept":"*/*","user-agent":"Mozilla/4.0 (compatible; MSIE 6.0; Windows NT 5.1; SV1)","host":"diabetescirkel.local","te":"deflate,gzip;q=0.3","cookie2":"$Version=\"1\"","cookie":"_refactormycode_session_id=a1b2n3jk4k5; flash=%7B%7D","METHOD":"POST","VERSION":"HTTP/1.1","URI":"/codes/58-tracking-file-downloads-automatically-in-google-analytics-with-prototype/refactors","PATTERN":"/"},1:a, '
        request = Request.parse("#{uuid} #{conn_id} #{msg}", "chroot")
        request.env['HTTP_COOKIE2'].should == '$Version="1"'

        request.should validate_with_lint
      end

      it 'shoud accept long query string' do
        msg = '/session 1476:{"PATH":"/session","x-forwarded-for":"127.0.0.1","host":"diabetescirkel.local","METHOD":"GET","VERSION":"HTTP/1.1","URI":"/session?open_id_complete=1&nonce=ytPOcwni&nonce=ytPOcwni&openid.assoc_handle=%7BHMAC-SHA1%7D%7B473e38fe%7D%7BJTjJxA%3D%3D%7D&openid.identity=http%3A%2F%2Fpalmade.myopenid.com%2F&openid.mode=id_res&openid.op_endpoint=http%3A%2F%2Fwww.myopenid.com%2Fserver&openid.response_nonce=2007-11-29T01%3A19%3A35ZGA5FUU&openid.return_to=http%3A%2F%2Flocalhost%3A3000%2Fsession%3Fopen_id_complete%3D1%26nonce%3DytPOcwni%26nonce%3DytPOcwni&openid.sig=lPIRgwpfR6JAdGGnb0ZjcY%2FWjr8%3D&openid.signed=assoc_handle%2Cidentity%2Cmode%2Cop_endpoint%2Cresponse_nonce%2Creturn_to%2Csigned%2Csreg.email%2Csreg.nickname&openid.sreg.email=palmade%40caresharing.eu&openid.sreg.nickname=palmade","QUERY":"open_id_complete=1&nonce=ytPOcwni&nonce=ytPOcwni&openid.assoc_handle=%7BHMAC-SHA1%7D%7B473e38fe%7D%7BJTjJxA%3D%3D%7D&openid.identity=http%3A%2F%2Fpalmade.myopenid.com%2F&openid.mode=id_res&openid.op_endpoint=http%3A%2F%2Fwww.myopenid.com%2Fserver&openid.response_nonce=2007-11-29T01%3A19%3A35ZGA5FUU&openid.return_to=http%3A%2F%2Flocalhost%3A3000%2Fsession%3Fopen_id_complete%3D1%26nonce%3DytPOcwni%26nonce%3DytPOcwni&openid.sig=lPIRgwpfR6JAdGGnb0ZjcY%2FWjr8%3D&openid.signed=assoc_handle%2Cidentity%2Cmode%2Cop_endpoint%2Cresponse_nonce%2Creturn_to%2Csigned%2Csreg.email%2Csreg.nickname&openid.sreg.email=palmade%40caresharing.eu&openid.sreg.nickname=palmade","PATTERN":"/"},0:, '
        request = Request.parse("#{uuid} #{conn_id} #{msg}", "chroot")

        request.env['QUERY_STRING'].should == 'open_id_complete=1&nonce=ytPOcwni&nonce=ytPOcwni&openid.assoc_handle=%7BHMAC-SHA1%7D%7B473e38fe%7D%7BJTjJxA%3D%3D%7D&openid.identity=http%3A%2F%2Fpalmade.myopenid.com%2F&openid.mode=id_res&openid.op_endpoint=http%3A%2F%2Fwww.myopenid.com%2Fserver&openid.response_nonce=2007-11-29T01%3A19%3A35ZGA5FUU&openid.return_to=http%3A%2F%2Flocalhost%3A3000%2Fsession%3Fopen_id_complete%3D1%26nonce%3DytPOcwni%26nonce%3DytPOcwni&openid.sig=lPIRgwpfR6JAdGGnb0ZjcY%2FWjr8%3D&openid.signed=assoc_handle%2Cidentity%2Cmode%2Cop_endpoint%2Cresponse_nonce%2Creturn_to%2Csigned%2Csreg.email%2Csreg.nickname&openid.sreg.email=palmade%40caresharing.eu&openid.sreg.nickname=palmade'

        request.should validate_with_lint
      end
    end
  end
end
