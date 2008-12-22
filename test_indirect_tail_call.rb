
class TestGoto
  attr_accessor :states, :str, :depth

  NEWLINE = "\n"
  TAB = "\x20\x20"

  def initialize
    @states = []
    @str = ''
    @depth = 0
  end

  def dump_symbol(obj)
    @str << ":#{obj}"
    next_object
  end

  def dump_integer(obj)
    begin
      raise "test except"
    rescue Exception
      @str << "#{obj}"
      next_object
    end
  end

  def dump_array(obj)
    if obj.size == 0
      @str << '[]'
      next_object
    else
      @depth += 1
      @str << '['
      dump_array_element(obj, 0)
    end
  end

  def dump_array_element(obj, i)
    if i < obj.size
      @str << ',' if i > 0
      @str << NEWLINE + (TAB * @depth)
      @states << [:array, obj, i.succ]
      dump(obj[i])
    else
      @depth -= 1
      @str << NEWLINE + (TAB * @depth) + ']'
      next_object
    end
  end

  def next_object()
    if @states.empty?
      @str
    else
      type = @states.last.first

      case type
      when :array
        _, obj, i = @states.pop
        dump_array_element(obj, i)
      end
    end
  end

  def dump(obj)

    case obj
    when Array
      dump_array(obj)
    when Symbol
      dump_symbol(obj)
    when Integer
      dump_integer(obj)
    else
      raise "error: unknown object type '#{obj.class}'"
    end
  end
end

tg = TestGoto.new

arr = [:hello, [:no, 42, [[], :yes, 15, []]], 10]

arr << Array.new(1_000, Array.new(10, :foo))

puts tg.dump(arr)[0..129]

