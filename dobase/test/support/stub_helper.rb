# frozen_string_literal: true

# Minimal stand-in for minitest/mock, which minitest 6 no longer ships.
module StubHelper
  # Shape of the HTTParty response fields TwentyClient reads.
  FakeResponse = Struct.new(:code, :parsed_response, keyword_init: true)

  # Replaces `object.method_name` for the duration of the block and restores the
  # original (or removes the stub) in `ensure`, even when the block raises.
  # A callable replacement is invoked with the call's arguments; any other value
  # is returned as-is.
  def with_stub(object, method_name, replacement)
    method_name = method_name.to_sym
    klass = object.singleton_class
    original = klass.instance_method(method_name) if own_method?(klass, method_name)
    was_private = klass.private_method_defined?(method_name, false)

    klass.define_method(method_name) do |*args, **kwargs, &blk|
      replacement.respond_to?(:call) ? replacement.call(*args, **kwargs, &blk) : replacement
    end
    klass.send(:private, method_name) if was_private

    yield
  ensure
    klass.send(:remove_method, method_name) if klass && own_method?(klass, method_name)
    if original
      klass.define_method(method_name, original)
      klass.send(:private, method_name) if was_private
    end
  end

  private

  def own_method?(klass, method_name)
    klass.method_defined?(method_name, false) || klass.private_method_defined?(method_name, false)
  end
end
