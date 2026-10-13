lake build Formal.$1
npx ajv-cli validate --spec=draft2020 -s ../docs/property-catalogue/property.schema.json -d Formal/$1/properties.json
