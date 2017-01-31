requires 'Forklift'         => 0.01;
requires 'strictures'       => 2.000000;
requires 'namespace::clean' => 0.24;
requires 'Moo'              => 2.000000;
requires 'Type::Tiny'       => 1.000005;
requires 'Scalar::Util'     => 0;
requires 'Parallel::ForkManager' => 1.16;

on test => sub {
   requires 'Test2::Bundle::Extended' => '0.000051';
};
