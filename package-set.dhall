let upstream =
      https://github.com/dfinity/vessel-package-set/releases/download/mo-0.8.8-20230505/package-set.dhall

let packages = [
  { name = "btree"
  , repo = "https://github.com/canscale/StableHeapBTreeMap"
  , version = "v0.3.2"
  , dependencies = [ "base" ]
  },
  { name = "testing"
  , repo = "https://github.com/internet-computer/testing.mo"
  , version = "v0.1.3"
  , dependencies = [] : List Text
  },
]

in  upstream # packages