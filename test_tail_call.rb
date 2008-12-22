
module TestFunc

  def self.to_two(n)
    if n <= 2
      2
    else
      to_two(n - 1)
    end
  end

  def self.fib(n, a = 0, b = 1)
    if n <= 0
      a
    else
      fib(n - 1, b, a + b)
    end
  end

  def self.foldl(f, acc, arr, i = 0)
    if i >= arr.size
      acc
    else
      foldl(f, f.call(acc, arr[i]), arr, i.succ)
    end
  end

  def self.clos(func = nil)
    if func
      c = 111
      func.call
    else
      b = 5
      c = 25
      func = lambda do b + c == 30 end
      clos(func)
    end
  end

  def self.catch_self(n = 0)
    if n >= 10
      raise "bad"
    else
      begin
        catch_self(n.succ)
      rescue Exception
        :good
      end
    end
  end

  def self.yucky(a, b = 10)
    if b <= 0
      begin
        raise "bye"
      rescue Exception
        777
      end
    elsif a <= 0
      begin
        yucky(a, b - 1)
      rescue Exception
        nil
      end
    else
      begin
        yucky(a - 1)
      rescue Exception
        false
      end
    end
  end

  def self.gross(action = nil, num = 0)
    case action
    when :add
      begin
        gross(:return, 5 + 5)
      rescue Exception
        nil
      end
    when :return
      begin
        raise "bye"
      rescue Exception
        num
      end
    else
      begin
        raise "to tail"
      rescue Exception
        # not a genuine tail call because of 
        # clear_exception after send_stack
        gross(:add)
      end
    end
  end

  # this doesn't run in constant space probably because block
  # parameters aren't necessarily locals. BlockEnvironment#call seems
  # to allocate a tuple from the general heap to hold
  # the arguments that are passed to it
  #
  def self.not_optimized_0
    z = lambda do |f, n|
          if n <= 2
            2
          else
            f.call(f, n - 1)
          end
        end
    num = 4_000_000

    z.call(z, num)
  end

  def self.evil_eval(which)
    mutate = 7531
    case which
    when :module_eval
      Module.module_eval("if mutate == 7531; mutate = 6420; else; :bad; end")
    when :instance_eval
      "".instance_eval("if mutate == 7531; mutate = 6420; else; :bad; end")
    when :eval
      eval("if mutate == 7531; mutate = 6420; else; :bad; end")
    else
      :bad
    end
  end

  # iterative fib
  #
  def self.fub(n)
    a = 0
    b = 1
    while n > 0
      tmp = a + b
      a = b
      b = tmp
      n -= 1
    end
    a
  end
end

class Hi
  def there(hello)
    hello.there(self)
  end
end

class Hello
  attr_accessor :num

  def there(hi)
    if @num < 0
      :okay
    else
      @num -= 1
      hi.there(self)
    end
  end
end

immutable_first_local = :good

puts TestFunc.evil_eval(:module_eval)
puts immutable_first_local == :good
puts TestFunc.evil_eval(:instance_eval)
puts immutable_first_local == :good
puts TestFunc.evil_eval(:eval)
puts immutable_first_local == :good

puts

hi = Hi.new
hello = Hello.new

hello.num = 10_000_000
puts hi.there(hello)



num = 6_000_000

puts TestFunc.fib(num / 1_000) == TestFunc.fub(num / 1_000)

puts TestFunc.to_two(num)
puts TestFunc.clos
puts TestFunc.catch_self

sum = lambda do |acc, num| acc + num end
numbers = Array.new(1_000_000, 5)

puts TestFunc.foldl(sum, 0, numbers) == numbers.inject(0, &sum)

reverse = lambda do |acc, obj| acc.unshift(obj) end
numbers = (0..9_999).to_a

puts TestFunc.foldl(reverse, [], numbers) == numbers.inject([], &reverse)

