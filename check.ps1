winget install -e --id Git.Git -h --accept-package-agreements
winget install -e --id GitHub.cli -h --accept-package-agreements
winget install wingetcreate -h --accept-package-agreements
Install-Module -Name powershell-yaml
Import-Module powershell-yaml
gh auth setup-git
gh repo clone "Rust-Winget-Bot/winget-pkgs"
cd winget-pkgs
git pull upstream master
git push
$lastFewVersions = git ls-remote --sort=-v:refname --tags https://github.com/rust-lang/rust.git | Foreach {(($_ -split '\t')[1]).Substring(10)} | Where-Object {!$_.Contains('release') -and !$_.Contains('^')} | Select -First 3;
$myPrs = gh pr list --author "Rust-Winget-Bot" --repo "microsoft/winget-pkgs" --state=all | Foreach {((($_ -split '\t')[2]) -split ':')[1]};
foreach ($toolchain in @("MSVC", "GNU")) {
    $toolchainLower = $toolchain.ToLower();
    $publishedVersions = winget show --id Rustlang.Rust.$toolchain --versions | Select -Skip 4 -First 5;
    foreach ($version in $lastFewVersions) {
        if ($publishedVersions.Contains($version)) {
            continue;
        } else {
            if ($myPrs -and $myPrs.Contains("rust-$version-$toolchainLower")) {
                continue;
            }
            git checkout master;
            git checkout -b rust-$version-$toolchainLower;
            if ($toolchain -eq "MSVC") {
                wingetcreate update --urls https://static.rust-lang.org/dist/rust-$version-aarch64-pc-windows-msvc.msi https://static.rust-lang.org/dist/rust-$version-i686-pc-windows-msvc.msi https://static.rust-lang.org/dist/rust-$version-x86_64-pc-windows-msvc.msi --version $version Rustlang.Rust.MSVC
            } else {
                wingetcreate update --urls https://static.rust-lang.org/dist/rust-$version-i686-pc-windows-gnu.msi https://static.rust-lang.org/dist/rust-$version-x86_64-pc-windows-gnu.msi --version $version Rustlang.Rust.GNU
            }
            # Update fields which wingetcreate doesn't update correctly
            $yamlPath = "manifests/r/Rustlang/Rust/$toolchain/$version/Rustlang.Rust.$toolchain.installer.yaml";
            $yamlData = Get-Content $yamlPath;
            $yamlObject = ConvertFrom-YAML $yamlData
            foreach ($installer in $yamlObject.Installers) {
                $bits = if ($installer.Architecture -eq "x86") {
                    "32-bit"
                } elseif ($installer.Architecture -eq "x64") {
                    "64-bit"
                } elseif ($installer.Architecture -eq "arm64") {
                    "arm64"
                };
                $newEntry = New-Object –TypeNamePSObject;
                $productCode = "";
                if ($installer.Architecture -eq "x86") {
                    if ($toolchain -eq "MSVC") {
                        $productCode = "{FBAC7273-35AB-4942-8B6A-A3407C4558C2}"
                    } elseif ($toolchain -eq "GNU") {
                        $productCode = "{4120AD8B-3C6B-4EBD-9646-DF20F3120208}"
                    }
                } elseif ($installer.Architecture -eq "x64") {
                    if ($toolchain -eq "MSVC") {
                        $productCode = "{F89628A9-D84F-486B-83F5-092007FA03C9}"
                    } elseif ($toolchain -eq "GNU") {
                        $productCode = "{C228EF57-CC84-4973-A41B-60C8861E51FF}"
                    }
                } elseif ($installer.Architecture -eq "arm64") {
                    if ($toolchain -eq "MSVC") {
                        $productCode = "{4205D4CC-DCFE-4A97-9B95-E9B46D3FED71}"
                    } elseif ($toolchain -eq "GNU") {
                        # Nothing to do, arm64 gnu doesn't exist.
                    }
                }
                $newEntry | Add-Member -Name ProductCode -Value $productCode
                $newEntry | Add-Member -Name DisplayName -Value "Rust $version ($toolchain $bits)";
                $newEntry | Add-Member -Name DisplayVersion -Value "$version.0"
                $installer.AppsAndFeaturesEntries = @($newEntry);
            }
            $newYamlData = ConvertTo-YAML $yamlObject;
            Set-Content -Path $yamlPath -Value $newYamlData;
            git add --all .
            git commit -m"add Rustlang.Rust.$toolchain version $version"
            git push -u origin rust-$version-$toolchainLower;
            # Uncomment this once we've seen it work a few times and are happy with it.
            # gh pr create --title "add Rustlang.Rust.$toolchain version $version" --body "I'm a bot and this PR was opened automatically. If there's something wrong, please file an issue at https://github.com/Rust-Winget-Bot/bot-issues/issues"
        }
    }
}
