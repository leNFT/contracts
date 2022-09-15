import abi from "web3-eth-abi";
import { utils } from "ethers";
import { getMessage } from "eip-712";
require("dotenv").config();

const collection = "0xa513E6E4b8f2a923D98304ec87F64353C4D5C853";
const tokenId = "0";

async function main() {
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
      amount: "100000000000000000000",
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
      verifyingContract: "0x0DCd1Bf9A1b36cE34237eEaFef220932846BCD82",
    },
    message: {
      request:
        "0x0000000000000000000000000000000000000000000000000000000000000000",
      deadline: "1694732504",
      payload: payload,
    },
  };

  const signingKey = new utils.SigningKey(process.env.SERVER_SIGNING_KEY);

  // Get a signable message from the typed data
  const message = getMessage(typedData, true);

  // Sign the message with the private key
  const { r, s, v } = signingKey.signDigest(message);

  const sigPacket = {
    v: v,
    r: r,
    s: s,
    request:
      "0x0000000000000000000000000000000000000000000000000000000000000000",
    deadline: "1694732504",
    payload: payload,
  };

  console.log(sigPacket);
}

// We recommend this pattern to be able to use async/await everywhere
// and properly handle errors.
main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
