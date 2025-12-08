# find_latest_version_of_file.sh

A fast, parallel file version finder.

## Usage

```
./find_latest_version_of_file.sh --root DIR --file NAME -N 50 -P 28
./find_latest_version_of_file.sh --root DIR --file-pattern "*jsig*.md" -N 100 -P 28
```

## CSV/JSON Output

```
--csv results.csv
--json results.json
```

## Example

```
./find_latest_version_of_file.sh \
  --root /backups \
  --file JSIGConvert.md \
  -N 50 \
  -P 28 \
  --csv latest.csv \
  --json latest.json
```
