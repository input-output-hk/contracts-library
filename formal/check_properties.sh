lake build Formal.$1
npx ajv-cli validate --spec=draft2020 -s Formal/$1/schema.json -d Formal/$1/properties.json
