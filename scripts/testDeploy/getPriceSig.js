import fetch from "node-fetch";
import abi from "web3-eth-abi";
import { utils } from "ethers";
import { getMessage } from "eip-712";

const collection = "0x0165878A594ca255338adfa4d48449f69242Eb8F";
const tokenId = "0";

async function main() {
  const options = {
    method: "GET",
    headers: {
      Accept: "application/json",
      "X-API-KEY": "aa5381da-b86b-4765-84a4-e31743a9ce70",
    },
  };

  const tokenBestBidResponse = await fetch(
    "https://api.modulenft.xyz/api/v1/opensea/token/bestBid?tokenId=" +
      tokenId +
      "&collection=" +
      collection,
    options
  ).catch((err) => console.error(err));
  const tokenBestBid = await tokenBestBidResponse.json();

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
      amount: "500000000000000000000", //tokenBestBid.info.bestBid["price"] * 10000,
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
      verifyingContract: "0xa51c1fc2f0d1a1b8494ed1fe312d7c3a78ed91c0",
    },
    message: {
      request:
        "0x0000000000000000000000000000000000000000000000000000000000000000",
      deadline: "1659961474",
      payload: payload,
    },
  };

  const signingKey = new utils.SigningKey(process.env.SIGNING_KEY);

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
    deadline: "1659961474",
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
