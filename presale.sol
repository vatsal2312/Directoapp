// SPDX-License-Identifier: MIT
pragma solidity 0.8.9;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/Address.sol";

/**
@title presale contract by d3Launch 
@author https://gitlab.com/directo3Inc
@notice This preslae Contract is part of directo3Inc Ecosystem
*/
contract TokenPresale is ReentrancyGuard, Ownable {
    event Purchase(address indexed buyer, uint256 amount); // event to emit when a purchase is made

    struct Presale {
        IERC20 token;
        uint256 startTime; // start time of the presale
        uint256 endTime; // end time of the presale
        uint256 tokenPrice; // price of one token in wei
        uint256 minPurchaseAmount; // minimum purchase amount in wei
        uint256 maxPurchaseAmount; // maximum purchase amount in wei
        uint256 liquidityLock; // percentage of liquidityLock
        uint256 liquidityLockPeriod; // period of liquidityLock
    }

    struct Vesting {
        uint256 cycle; // period of one vesting cycle
        uint256 releasePercentage; // percentage to release each cycle
        uint256 period; // total vesting period
    }

    Presale public presale;
    Vesting public vesting;

    IERC20 public immutable DRTP; // DRTP address
    address public immutable D3VAULT; // payment splitter address
    bool public preSaleFundsWithdrawn;
    uint256 public totalTokensSold; // total number of tokens sold

    mapping(address => uint256) public purchasedTokens; // mapping of addresses to their purchased token amount
    mapping(address => uint256) public claimedVestedTokens; // mapping of addresses to their claimed vested tokens
    address[] public investors; // list of investors and key value of purchasedTokens mapping

    constructor(
        Presale memory _presale,
        Vesting memory _vesting,
        bool feeInDRTP,
        IERC20 _drtp,
        address _d3Vault,
        uint256 fee
    ) payable {
        require(
            _presale.liquidityLock <= 100,
            "liquidityLock greater than 100"
        );
        require(
            _presale.liquidityLockPeriod > 0,
            "liquidityLockPeriod less than block time"
        );
        require(
            _vesting.releasePercentage <= 100,
            "releasePercentage greater than 100"
        );
        require(_vesting.cycle != 0, "vesting.cycle cannot be 0");
        require(_vesting.period != 0, "vesting.period cannot be 0");

        DRTP = _drtp;
        D3VAULT = _d3Vault;

        if (feeInDRTP) {
            DRTP.transferFrom(msg.sender, D3VAULT, fee);
        } else {
            Address.sendValue(payable(D3VAULT), fee);
        }

        presale = Presale({
            liquidityLock: _presale.liquidityLock,
            liquidityLockPeriod: _presale.liquidityLockPeriod,
            token: _presale.token,
            startTime: _presale.startTime,
            endTime: _presale.endTime,
            tokenPrice: _presale.tokenPrice,
            minPurchaseAmount: _presale.minPurchaseAmount,
            maxPurchaseAmount: _presale.maxPurchaseAmount
        });

        vesting = Vesting({
            cycle: _vesting.cycle,
            releasePercentage: _vesting.releasePercentage,
            period: _vesting.period
        });
    }

    //==================  External Functions    ==================//

    function purchaseTokens() external payable nonReentrant {
        require(this.presaleIsActive(), "Presale not active");
        require(
            msg.value >= presale.minPurchaseAmount &&
                msg.value <= presale.maxPurchaseAmount,
            "Invalid purchase amount"
        );

        // %2 investor fee to D3VAULT
        Address.sendValue(payable(D3VAULT), (msg.value * 2) / 100);

        uint256 amount = (msg.value - ((msg.value * 2) / 100)) /
            presale.tokenPrice;
        require(
            presale.token.balanceOf(address(this)) - totalTokensSold >= amount,
            "Insufficient token balance in presale contract"
        );
        totalTokensSold += amount;
        if (purchasedTokens[msg.sender] == 0) {
            investors.push(msg.sender);
        }
        purchasedTokens[msg.sender] += amount;
        emit Purchase(msg.sender, amount);
    }

    //==================  Administrative Functions    ==================//

    function withdrawFunds() external nonReentrant onlyOwner {
        require(preSaleFundsWithdrawn == false, "Funds already withdrawn");

        require(presaleIsActive() == false, "Presale Is Active");

        preSaleFundsWithdrawn = true;

        uint256 contractBalance = address(this).balance;
        // 4% fee to D3VAULT
        Address.sendValue(payable(D3VAULT), (contractBalance * 4) / 100);

        contractBalance = contractBalance - ((contractBalance * 4) / 100);

        contractBalance =
            contractBalance -
            ((contractBalance * presale.liquidityLock) / 100);

        // sending funds excluding liquidity lock amount to presale owner
        Address.sendValue(payable(owner()), contractBalance);

        // sending non sold tokens back to presale owner
        uint256 remainingTokens = presale.token.balanceOf(address(this)) -
            totalTokensSold;
        if (remainingTokens > 0)
            presale.token.transfer(owner(), remainingTokens);
    }

    function withdrawLockedFunds() external nonReentrant onlyOwner {
        require(
            block.timestamp >= presale.liquidityLockPeriod + presale.endTime,
            "Liquidity Lock Time Active"
        );

        Address.sendValue(payable(msg.sender), address(this).balance);
    }

    //==================  Public Functions    ==================//

    function claim() public {
        require(purchasedTokens[msg.sender] > 0, "Not an investor");
        uint256 totalClaimableNow = claimableTokens();
        claimedVestedTokens[msg.sender] += totalClaimableNow;
        presale.token.transfer(msg.sender, totalClaimableNow);
    }

    //==================  Read only Functions    ==================//

    function claimableTokens() public view returns (uint256) {
        uint256 totalTokensInvestorShouldHaveClaimed = ((purchasedTokens[
            msg.sender
        ] * vesting.releasePercentage) / 100) * currentVestingCycle();

        if (
            totalTokensInvestorShouldHaveClaimed >
            purchasedTokens[msg.sender] ||
            block.timestamp >= presale.endTime + vesting.period
        ) {
            totalTokensInvestorShouldHaveClaimed = purchasedTokens[msg.sender];
        }

        return
            totalTokensInvestorShouldHaveClaimed -
            claimedVestedTokens[msg.sender];
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

    function currentVestingCycle() public view returns (uint256) {
        return (block.timestamp - presale.endTime) / vesting.cycle;
    }

    //==================  Internal Functions    ==================//
}
