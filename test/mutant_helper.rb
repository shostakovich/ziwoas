# Entry point for `mutant run`.
#
# Mutant runs the tests itself, so minitest's at_exit runner must never fire:
# it would run the whole suite again inside every killfork. Claiming the hook
# before rails/test_help installs it is the only way to keep it out.
ENV["SKIP_COVERAGE"] = "1"

require "minitest"
Minitest.class_variable_set(:@@installed_at_exit, true)

require "test_helper"

Rails.application.eager_load!
