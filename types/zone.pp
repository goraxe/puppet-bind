# @summary Type definition for BIND's `zone` statement
type Bind::Zone = Struct[{
  name => String[1],
  Optional['allow-transfer'] => Array[Variant[Stdlib::Host, Stdlib::IP::Address]],
  Optional['also-notify'] => Array[Variant[Stdlib::Host, Stdlib::IP::Address]],
  Optional['auto-dnssec'] => Enum['allow', 'maintain', 'off'],
  Optional['class'] => Enum['IN', 'HS', 'hesiod', 'CHAOS'],
  Optional['file'] => Stdlib::Absolutepath,
  Optional['forward'] => Enum['first', 'only'],
  Optional['forwarders'] => Array[Stdlib::Host],
  Optional['in-view'] => String[1],
  Optional['inline-signing'] => Variant[Boolean, Stdlib::Yes_no],
  Optional['key-directory'] => Stdlib::Absolutepath,
  Optional['masters'] => Array[Stdlib::Host],
  Optional['primaries'] => Array[Stdlib::Host],
  Optional['type'] => Enum[
    'primary',
    'master',
    'secondary',
    'slave',
    'mirror',
    'hint',
    'stub',
    'static-stub',
    'forward',
    'redirect',
    'delegation-only'
  ],
}]
