-- Minimal init for plenary.test_harness
-- Paths are already set via --cmd in Makefile
-- Individual test files call setup() with desired opts

-- Make test helpers require-able from tests/
-- This adds ./tests/?.lua and ./tests/?/init.lua lookup
package.path = "./tests/?.lua;./tests/?/init.lua;" .. package.path
