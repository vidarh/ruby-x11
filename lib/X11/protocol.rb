module X11
  module Protocol
    # endianess of your machine
    BYTE_ORDER = case [1].pack("L")
      when "\0\0\0\1" then "B".ord
      when "\1\0\0\0" then "l".ord
      else
        raise ByteOrderError.new "Cannot determine byte order"
      end

    MAJOR = 11
    MINOR = 0
  end
end
