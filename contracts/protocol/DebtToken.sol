// SPDX-License-Identifier: agpl-3.0
pragma solidity 0.8.17;

import {ERC721EnumerableUpgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC721/extensions/ERC721EnumerableUpgradeable.sol";
import {ERC721Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC721/ERC721Upgradeable.sol";
import {IDebtToken} from "../interfaces/IDebtToken.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {IAddressesProvider} from "../interfaces/IAddressesProvider.sol";

contract DebtToken is
    Initializable,
    ERC721Upgradeable,
    ERC721EnumerableUpgradeable,
    IDebtToken
{
    IAddressesProvider private _addressProvider;

    // Initialize the market
    function initialize(
        IAddressesProvider addressesProvider,
        string memory name,
        string memory symbol
    ) external initializer {
        __ERC721_init(name, symbol);
        _addressProvider = addressesProvider;
    }

    modifier onlyMarket() {
        require(
            msg.sender == address(_addressProvider.getMarketAddress()),
            "Caller must be Market contract"
        );
        _;
    }

    function mint(address to, uint256 loanId) external override onlyMarket {
        super._safeMint(to, loanId);

        emit Mint(to, loanId);
    }

    function burn(uint256 loanId) external override onlyMarket {
        super._burn(loanId);

        emit Burn(loanId);
    }

    function _beforeTokenTransfer(
        address from,
        address to,
        uint256 tokenId
    ) internal override(ERC721Upgradeable, ERC721EnumerableUpgradeable) {
        super._beforeTokenTransfer(from, to, tokenId);
    }

    function supportsInterface(bytes4 interfaceId)
        public
        view
        override(ERC721Upgradeable, ERC721EnumerableUpgradeable)
        returns (bool)
    {
        return super.supportsInterface(interfaceId);
    }
}
