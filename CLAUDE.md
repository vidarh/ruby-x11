# Ruby X11 Development Guidelines

## Build Commands
- Install dependencies: `bundle install`
- Run all tests: `rake test`
- Run single test: `ruby test/specific_test.rb`

## Code Style
- Indentation: 2 spaces
- Naming: snake_case for methods/variables, CamelCase for classes
- Constants: ALL_CAPS or CamelCase (matching X11 protocol names)
- Methods: One-line with `=` for simple methods (Ruby 3 syntax)
- Error handling: Custom X11 error hierarchy (X11::BasicError, etc.)
- Imports: require_relative for internal files, require for gems

## Organization
- Core functionality in lib/X11.rb
- Components in lib/X11/ directory
- Protocol definitions using DSL in form.rb
- Test files in test/ directory with _test.rb suffix

## Testing
- Uses Minitest::Spec syntax: `_(object).must_equal expected`
- Tests require helper.rb which sets up the environment
- Mock objects for testing sockets/connections

## Documentation
- Comments for complex logic
- Reference X11 protocol documentation when implementing specs

## Adding X11 Protocol Requests
1. Define request form in lib/X11/form.rb:
   ```ruby
   class XRenderFreePicture < BaseForm
     field :req_type, Uint8
     field :render_req_type, Uint8, value: 7
     field :request_length, Uint16, value: 2
     field :picture, Uint32
   end
   ```
2. Add helper method in lib/X11/display.rb:
   ```ruby
   def render_free_picture(picture)
     write_request(Form::XRenderFreePicture.new(render_opcode, picture))
   end
   ```
3. Update X11::VERSION in lib/X11/version.rb after adding new functionality