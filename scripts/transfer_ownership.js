/****************************************************************
  TRANSFER OWNERSHIP
  Transfer the admin ownership of the upgradable contracts to gnosis safe
  ******************************************************************/

async function main() {
  const gnosisSafe = "0xeF3A51512A6aE613609081659F1dA27Db8Be4929";

  console.log("Transferring ownership of ProxyAdmin...");
  // The owner of the ProxyAdmin can upgrade our contracts
  await upgrades.admin.transferProxyAdminOwnership(gnosisSafe);
  console.log("Transferred ownership of ProxyAdmin to:", gnosisSafe);
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
