module example.org/shcounter

go 1.14

replace benchmark => ../../../../benchmark/common

replace github.com/UBC-NSS/pgo/distsys => ../../../../distsys

require (
	benchmark v0.0.0-00010101000000-000000000000 // indirect
	github.com/UBC-NSS/pgo/distsys v0.0.0-00010101000000-000000000000
)
