#  This module is an approximate ruby replacement for the libXau C library and the 
#  xauth(1) program. It reads and interprets the files (usually '~/.Xauthority') that 
#  hold authorization data used in connecting to X servers. Since it was written mainly 
#  for the use of X11::Protocol, its functionality is currently restricted to reading, 
#  not writing, of these files.

module X11
  class Auth
    FAILED = 0
    SUCCESS = 1
    AUTHENTICATE = 2

    ADDRESS_TYPES = {
      256 => :Local,
      65535 => :Wild,
      254 => :Netname,
      253 => :Krb5Principal,
      252 => :LocalHost,
      0 => :Internet,
      1 => :DECnet,
      2 => :Chaos
    }

    AuthInfo = Struct.new :family, :address, :display, :auth_name, :auth_data

    # Open an authority file, and create an object to handle it.
    # The filename will be taken from the XAUTHORITY environment variable,
    # if present, or '.Xauthority' in the user's home directory, or it may be overridden
    # by an argument.
    def initialize(path = ENV['XAUTHORITY'] || ENV['HOME'] + "/.Xauthority")
      @file = File.open(path)
    end

    # Get authentication data for a connection of type family to display display_id on host.
    # If family is 'Internet', the host will be translated into an appropriate address by gethostbyname().
    # If no data is found, returns nil
    def get_by_hostname(host, family, display_id)
      host = `hostname`.chomp if host == 'localhost' or host == '127.0.0.1' or host.nil?
      address = TCPSocket.gethostbyname(host) if family == :Internet # this line does nothing for now

      auth_data = nil

      # with each entry from XAuthority file
      until @file.eof?
        r = read()
        auth_data = r if r.display.empty? || display_id.to_i == r.display.to_i
      end

      reset
      return auth_data
    end

    # returns one entry from Xauthority file
    def read
      auth_info = [] << ADDRESS_TYPES[ @file.read(2).unpack('n').first ]

      4.times do
        length = @file.read(2).unpack('n').first
        auth_info << @file.read(length)
      end
      AuthInfo[*auth_info]
    end

    def reset
      @file.seek(0, IO::SEEK_SET)
    end

  end
end
