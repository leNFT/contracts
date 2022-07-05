// SPDX-License-Identifier: agpl-3.0
pragma solidity 0.8.15;

import {ERC721Enumerable} from "@openzeppelin/contracts/token/ERC721/extensions/ERC721Enumerable.sol";
import {ERC721} from "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import {IDebtToken} from "../interfaces/IDebtToken.sol";
import {IMarketAddressesProvider} from "../interfaces/IMarketAddressesProvider.sol";

contract DebtToken is ERC721, ERC721Enumerable, IDebtToken {
    IMarketAddressesProvider private _addressesProvider;

    constructor(
        string memory name,
        string memory symbol,
        IMarketAddressesProvider addressesProvider
    ) ERC721(name, symbol) {
        _addressesProvider = addressesProvider;
    }

    modifier onlyMarket() {
        require(
            _msgSender() == address(_addressesProvider.getMarketAddress()),
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
    ) internal override(ERC721, ERC721Enumerable) {
        super._beforeTokenTransfer(from, to, tokenId);
    }

    function supportsInterface(bytes4 interfaceId)
        public
        view
        override(ERC721, ERC721Enumerable)
        returns (bool)
    {
        return super.supportsInterface(interfaceId);
    }
}
