const abi = require("web3-eth-abi");
const { utils } = require("ethers");
const { getMessage } = require("eip-712");

function getPriceSig(collection, tokenId, amount, deadline, verifyingContract) {
  const requestID =
    "0x0000000000000000000000000000000000000000000000000000000000000000";
  console.log("deadline", deadline);
  const payload = abi.encodeParameter(
    {
      TokenPriceBoost: {
        collection: "address",
        tokenId: "uint256",
        amount: "uint256",
      },
    },
    {
      collection: collection,
      tokenId: tokenId,
      amount: amount, //"100000000000000000000",
    }
  );

  //Sign the payload and build the packet
  const typedData = {
    types: {
      EIP712Domain: [
        { name: "name", type: "string" },
        { name: "version", type: "string" },
        { name: "chainId", type: "uint256" },
        { name: "verifyingContract", type: "address" },
      ],
      VerifyPacket: [
        { name: "request", type: "bytes32" },
        { name: "deadline", type: "uint256" },
        { name: "payload", type: "bytes" },
      ],
    },
    primaryType: "VerifyPacket",
    domain: {
      name: "leNFT",
      version: "1",
      chainId: 31337,
      verifyingContract: verifyingContract,
    },
    message: {
      request: requestID,
      deadline: deadline, //"1694732504",
      payload: payload,
    },
  };

  const signingKey = new utils.SigningKey(
    "0x5c630579e78aeb31d9e22d52404ed4f189489aa9ed6d4161995b91b20a002764"
  );

  // Get a signable message from the typed data
  const message = getMessage(typedData, true);

  // Sign the message with the private key
  const { r, s, v } = signingKey.signDigest(message);

  const sigPacket = {
    v: v,
    r: r,
    s: s,
    request: requestID,
    deadline: deadline, //"1694732504",
    payload: payload,
  };

  return sigPacket;
}

module.exports = { getPriceSig };
