// SPDX-License-Identifier: MIT
pragma solidity 0.8.9;

import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/Address.sol";

/**
@title presale contract by d3Launch 
@author https://gitlab.com/directo3Inc
@notice This preslae Contract is part of directo3Inc Ecosystem
*/
contract NFTPresale is ReentrancyGuard, Ownable {
    event Purchase(address indexed buyer, uint256[] amount); // event to emit when a purchase is made

    struct Presale {
        IERC721 token;
        uint256 startTime; // start time of the presale
        uint256 endTime; // end time of the presale
        uint256 tokenPrice; // price of one token in wei
        uint256 minPurchaseAmount; // minimum purchase amount in wei
        uint256 maxPurchaseAmount; // maximum purchase amount in wei
    }

    struct NFT {
        uint256 id;
        bool claimed;
    }

    Presale public presale;

    IERC20 public immutable DRTP; // DRTP address
    address public immutable D3VAULT; // payment splitter address
    bool public preSaleFundsWithdrawn;
    uint256 public totalTokensSold; // total number of tokens sold

    mapping(address => NFT[]) public purchasedTokens; // mapping of addresses to their purchased token amount
    mapping(uint256 => bool) public NFTbought; // mapping of nft if bought or not
    address[] public investors; // list of investors and key value of purchasedTokens mapping

    constructor(
        Presale memory _presale,
        bool feeInDRTP,
        IERC20 _drtp,
        address _d3Vault,
        uint256 fee
    ) payable {
        DRTP = _drtp;
        D3VAULT = _d3Vault;

        if (feeInDRTP) {
            DRTP.transferFrom(msg.sender, D3VAULT, fee);
        } else {
            Address.sendValue(payable(D3VAULT), fee);
        }

        presale = Presale({
            token: _presale.token,
            startTime: _presale.startTime,
            endTime: _presale.endTime,
            tokenPrice: _presale.tokenPrice,
            minPurchaseAmount: _presale.minPurchaseAmount,
            maxPurchaseAmount: _presale.maxPurchaseAmount
        });
    }

    //==================  External Functions    ==================//

    function purchaseTokens(
        uint256[] calldata _nftId
    ) external payable nonReentrant {
        require(this.presaleIsActive(), "Presale not active");
        require(nftsAvailable(_nftId) == true, "NFT already bought");
        require(
            msg.value == (presale.tokenPrice * _nftId.length),
            "Invalid purchase amount"
        );

        // %2 investor fee to D3VAULT
        Address.sendValue(payable(D3VAULT), (msg.value * 2) / 100);

        if (purchasedTokens[msg.sender].length == 0) {
            investors.push(msg.sender);
        }
        for (uint256 i = 0; i < _nftId.length; i++) {
            NFTbought[_nftId[i]] = true;
            purchasedTokens[msg.sender].push(NFT(_nftId[i], false));
        }

        totalTokensSold += _nftId.length;
        emit Purchase(msg.sender, _nftId);
    }

    //==================  Administrative Functions    ==================//

    function withdrawFunds() external nonReentrant onlyOwner {
        require(preSaleFundsWithdrawn == false, "Funds already withdrawn");

        require(presaleIsActive() == false, "Presale Is Active");

        preSaleFundsWithdrawn = true;

        uint256 contractBalance = address(this).balance;
        // 3% fee to D3VAULT
        Address.sendValue(payable(D3VAULT), (contractBalance * 3) / 100);

        contractBalance = contractBalance - ((contractBalance * 3) / 100);

        // sending funds to presale owner
        Address.sendValue(payable(msg.sender), contractBalance);
    }

    function claimNonSoldNFT(
        uint256[] calldata _nftId
    ) external nonReentrant onlyOwner {
        require(presaleIsActive() == false, "Presale Is Active");
        require(nftsAvailable(_nftId) == true, "NFT already bought");

        for (uint256 i = 0; i < _nftId.length; i++) {
            presale.token.safeTransferFrom(address(this), owner(), _nftId[i]);
        }
    }

    function withdrawLockedFunds() external nonReentrant onlyOwner {
        require(
            block.timestamp >= presale.endTime,
            "Liquidity Lock Time Active"
        );

        Address.sendValue(payable(msg.sender), address(this).balance);
    }

    //==================  Public Functions    ==================//

    function claim() public nonReentrant {
        require(purchasedTokens[msg.sender].length > 0, "Not an investor");

        NFT[] memory totalClaimableNow = claimableTokens();

        for (uint256 i = 0; i < totalClaimableNow.length; ++i) {
            purchasedTokens[msg.sender][i].claimed = true;
            presale.token.safeTransferFrom(
                address(this),
                msg.sender,
                purchasedTokens[msg.sender][i].id
            );
        }
    }

    //==================  Read only Functions    ==================//

    function nftsAvailable(
        uint256[] calldata _nftId
    ) public view returns (bool) {
        uint256 counter;
        for (uint256 i = 0; i < _nftId.length; ++i) {
            if (NFTbought[_nftId[i]] == false) {
                if (presale.token.ownerOf(_nftId[i]) == address(this))
                    counter += 1;
            } else return false;
        }

        return counter == _nftId.length;
    }

    function claimableTokens() public view returns (NFT[] memory) {
        return purchasedTokens[msg.sender];
    }

    function presaleIsActive() public view returns (bool) {
        return
            block.timestamp >= presale.startTime &&
                block.timestamp <= presale.endTime
                ? true
                : false;
    }

    function totalInvestors() public view returns (uint256) {
        return investors.length;
    }

    //==================  Internal Functions    ==================//
}
