
module PrettyCM

  NEWLINE = "\n"
  TAB = "\x20\x20"

  PCM_TOKENS = / (?: \" (?: \\\\ | \\" | [^"] )* \" ) |
                 (?: [a-z][a-z0-9_]+ [\x20\n\r] (?: [0-9]+ [\x20\n\r] ){0,2} ) |
                 (?: [A-Za-z0-9+\-.]+ ) |
                 (?: \( [^)]* \) )
               /x

  REGEX_FLOAT = / \A [+-]? [0-9]+ \. [0-9]+ (?: e [+-]? [0-9]+ )? \Z /x
  REGEX_INTEGER = / \A \-? [0-9]+ \Z /x
  REGEX_INSTRUCTION = / \A [a-z][a-z0-9_]+ [\x20\n\r] (?: [0-9]+ [\x20\n\r] ){0,2} \Z /x
  REGEX_COMMENT = / \A \( [^)]* \) \Z /x

  # 'dir' must have trailing slash
  #
  def self.fetch_files(dir, recurse, &block)
    for entry in Dir.entries(dir)
      if entry != '.' and entry != '..'
        type = File.ftype(dir + entry)
        if type == 'directory' and recurse
          fetch_files(dir + entry + '/', recurse, &block)
        elsif type == 'file'
          block.call(dir + entry)
        end
      end
    end
  end

  def self.read_file(path)
    begin
      f = File.new(path, 'rb')
      str = f.read
      f.close
      str
    rescue Exception
      ''
    end
  end

  def self.write_file(path, str)
    f = File.new(path, 'wb')
    f.write(str)
    f.close
  end

  def self.replace_prefix(str, from, to)
    str.sub(Regexp.new('\\A' + Regexp.escape(from))) { to }
  end

  def self.replace_suffix(str, from, to)
    str.sub(Regexp.new(Regexp.escape(from) + '\\Z')) { to }
  end

  def self.to_byte(n)
    [n].pack('C')
  end

  def self.to_hex(n)
    s = '%x' % n
    if s.length % 2 == 1
      '0' + s
    else
      s
    end
  end

  def self.apply_escape_codes(str)
    str = str.gsub('\\') { '\\\\' }  # must happen first
    str = str.gsub('"')  { '\\"' }
    str = str.gsub("\t") { '\\t' }
    str = str.gsub("\n") { '\\n' }
    str = str.gsub("\r") { '\\r' }
    str = str.gsub("\v") { '\\v' }
    str = str.gsub("\0") { '\\z' }

    r = / [\x00-\x1F\x7F-\xFF] /x
    str.gsub(r) do |m|
      '\\' + to_hex(m[0])
    end
  end

  def self.reduce_escape_codes(str)
    r = / \\ (?: [tnrvz"\\] | [0-9a-fA-F]{2} ) /x
    str.gsub(r) do |m|
      case m
      when '\\\\' then '\\'
      when '\\"'  then '"'
      when '\\t'  then "\t"
      when '\\n'  then "\n"
      when '\\r'  then "\r"
      when '\\v'  then "\v"
      when '\\z'  then "\0"
      else
        to_byte(m[1..-1].hex)
      end
    end
  end

  def self.dump(obj, depth = 0)
    out = ''
    tabs = TAB * depth

    case obj
    when Rubinius::CompiledMethod
      out << "#{NEWLINE + tabs}" unless depth == 0
      out << "CompiledMethod 17"
      depth += 1
      out << dump(obj.hints, depth)
      out << dump(obj.__ivars__, depth)
      out << dump(obj.primitive, depth)
      out << dump(obj.name, depth)
      out << dump(obj.iseq, depth)
      out << dump(obj.stack_size, depth)
      out << dump(obj.local_count, depth)
      out << dump(obj.required_args, depth)
      out << dump(obj.total_args, depth)
      out << dump(obj.splat, depth)
      out << dump(obj.literals, depth)
      out << dump(obj.exceptions, depth)
      out << dump(obj.lines, depth)
      out << dump(obj.file, depth)
      out << dump(obj.local_names, depth)
      out << dump(obj.scope, depth)
      out << dump(obj.serial, depth)
    when NilClass
      out << "#{NEWLINE + tabs}Nil"
    when TrueClass
      out << "#{NEWLINE + tabs}True"
    when FalseClass
      out << "#{NEWLINE + tabs}False"
    when Integer, Float
      out << "#{NEWLINE + tabs}#{obj}"
    when Symbol
      str = apply_escape_codes(obj.to_s)
      out << "#{NEWLINE + tabs}Symbol \"#{str}\""
    when Rubinius::InstructionSequence
      i = 0
      obj = obj.decode
      out << "#{NEWLINE + tabs}InstructionSequence #{obj.size}"

      obj.each do |opcode|
        cmnt = "(#{i})"
        column_space = ' ' * (8 - cmnt.length)
        ins_str = opcode.join(' ')
        out << NEWLINE + tabs + TAB + cmnt + column_space + ins_str
        i += opcode.length
      end

      out
    when Rubinius::Tuple, Array
      out << NEWLINE + tabs
      out << (obj.kind_of?(Array) ? 'Array' : 'Tuple') + " #{obj.size}"
      depth += 1
      obj.each do |elem|
        out << dump(elem, depth)
      end
      out
    when Rubinius::SendSite
      str = apply_escape_codes(obj.name.to_s)
      out << "#{NEWLINE + tabs}SendSite \"#{str}\""
    when String
      str = apply_escape_codes(obj)
      out << "#{NEWLINE + tabs}String \"#{str}\""
    when ByteArray
      str = ''
      obj.each { |n| str << '\\' + to_hex(n) }
      out << "#{NEWLINE + tabs}ByteArray \"#{str}\""
    when Hash
      out << "#{NEWLINE + tabs}Hash #{obj.size}"
      depth += 1
      obj.each_pair do |key, val|
        out << dump([key, val], depth)
      end
      out
    when StaticScope
      out << "#{NEWLINE + tabs}StaticScope 2"
      depth += 1
      out << dump(obj.module, depth)
      out << dump(obj.parent, depth)
    when Class
      str = apply_escape_codes(obj.name)
      out << "#{NEWLINE + tabs}Class \"#{str}\""
    when Module
      str = apply_escape_codes(obj.name)
      out << "#{NEWLINE + tabs}Module \"#{str}\""
    when Regexp
      src = apply_escape_codes(obj.source)
      opt = obj.options
      out << "#{NEWLINE + tabs}Regexp \"#{src}\" #{opt}"
    else
      raise "error: PrettyCM.dump: unknown object type '#{obj.class}'"
    end
  end

  def self.load(str, tokens = str.scan(PCM_TOKENS), token = tokens.shift)

    case token
    when /\A\"/
      token = token.sub(/\A\"/,'').sub(/\"\Z/,'')
      reduce_escape_codes(token)
    when REGEX_INTEGER
      token.to_i
    when REGEX_FLOAT
      token.to_f
    when REGEX_INSTRUCTION
      arr = token.split(' ')
      arr.map do |elem|
        case elem
        when / \A [0-9]+ \Z /x
          elem.to_i
        else
          elem.to_sym
        end
      end
    when REGEX_COMMENT
      load(str, tokens)
    when 'CompiledMethod'
      cm = Rubinius::CompiledMethod.new
      useless                 = load(str, tokens)
      cm.hints                = load(str, tokens)
      cm.__ivars__            = load(str, tokens)
      cm.primitive            = load(str, tokens)
      cm.name                 = load(str, tokens)
      cm.iseq                 = load(str, tokens)
      cm.stack_size           = load(str, tokens)
      cm.local_count          = load(str, tokens)
      cm.required_args        = load(str, tokens)
      cm.total_args           = load(str, tokens)
      cm.splat                = load(str, tokens)
      cm.literals             = load(str, tokens)
      cm.exceptions           = load(str, tokens)
      cm.lines                = load(str, tokens)
      cm.file                 = load(str, tokens)
      cm.local_names          = load(str, tokens)
      cm.scope                = load(str, tokens)
      cm.serial               = load(str, tokens)
      cm
    when 'Nil'
      nil
    when 'True'
      true
    when 'False'
      false
    when 'Symbol'
      load(str, tokens).to_sym
    when 'InstructionSequence'
      encoder = Rubinius::InstructionSequence::Encoder.new
      layered_iseq = []
      size = load(str, tokens)

      size.times do
        layered_iseq << load(str, tokens)
      end

      encoder.encode_stream(layered_iseq)
    when 'Tuple', 'Array'
      size = load(str, tokens)
      arr = case token
            when 'Array'
              Array.new(size)
            when 'Tuple'
              Rubinius::Tuple.new(size)
            end

      (0...size).each do |i|
        arr[i] = load(str, tokens)
      end

      arr
    when 'SendSite'
      name = load(str, tokens).to_sym
      Rubinius::SendSite.new(name)
    when 'String'
      load(str, tokens)
    when 'ByteArray'
      bytes = load(str, tokens)
      size = bytes.size
      ba = ByteArray.new(size)

      bytes.each_with_index do |c, i|
        ba[i] = c[0]
      end

      ba
    when 'Hash'
      hsh = {}
      size = load(str, tokens)

      size.times do
        key, val = load(str, tokens)
        hsh[key] = val
      end

      hsh
    when 'StaticScope'
      useless = load(str, tokens)
      useless = load(str, tokens)
      useless = load(str, tokens)
      nil
    when 'Class', 'Module'
      useless = load(str, tokens)
      nil
    when 'Regexp'
      src = load(str, tokens)
      opt = load(str, tokens)
      Regexp.new(src, opt)
    when 'NaN'
      0.0 / 0.0
    when 'Infinity'
      1.0 / 0.0
    when '-Infinity'
      -1.0 / 0.0
    else
      raise "error: PrettyCM.load: bad token '#{token}'"
    end
  end
end

