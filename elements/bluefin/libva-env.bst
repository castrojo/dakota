kind: import

sources:
- kind: local
  path: files/vaapi-env

config:
  target: "%{indep-libdir}/environment.d/"
